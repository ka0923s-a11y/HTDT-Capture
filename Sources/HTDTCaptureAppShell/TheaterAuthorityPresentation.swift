import Foundation
import HTDTCaptureCore

/// Operator-facing names for the theater-authority enumerations
/// (issue #365 FORM-10). Persisted `rawValue` schema tokens never
/// surface in the primary form path — every picker shows a localized
/// human label while the record keeps its canonical token. `unknown`
/// is a deliberate attested answer everywhere it exists, never hidden
/// or grouped with invalid input.
public enum TheaterAuthorityPresentation {

    /// Footnote shown under pickers where `unknown` is a first-class
    /// answer — explains it is recorded deliberately rather than
    /// treated as missing input (issue #365).
    public static var unknownIsRecordedNote: String {
        String(
            localized:
                "Choosing “Unknown” saves an explicit unconfirmed answer — it is not an error."
        )
    }

    public static func hostClassificationName(
        _ value: SurfaceHostClassification
    ) -> String {
        switch value {
        case .roomBoundary:
            return String(localized: "Room boundary")
        case .objectSurface:
            return String(localized: "Object surface")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    public static func constructionKindName(
        _ value: SurfaceConstructionKind
    ) -> String {
        switch value {
        case .gypsumDrywall:
            return String(localized: "Gypsum drywall")
        case .concreteMasonry:
            return String(localized: "Concrete / masonry")
        case .glass:
            return String(localized: "Glass")
        case .woodPanel:
            return String(localized: "Wood panel")
        case .carpet:
            return String(localized: "Carpet")
        case .hardFloor:
            return String(localized: "Hard floor")
        case .fabric:
            return String(localized: "Fabric")
        case .other:
            return String(localized: "Other")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    public static func constructionSourceName(
        _ value: ConstructionObservationSource
    ) -> String {
        switch value {
        case .userObservation:
            return String(localized: "My observation")
        case .installerOrBuildRecord:
            return String(localized: "Installer or build record")
        case .manufacturerReference:
            return String(localized: "Manufacturer reference")
        case .catalogReference:
            return String(localized: "Catalog reference")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func problemSurfaceKindName(
        _ value: ProblemSurfaceKind
    ) -> String {
        switch value {
        case .mirror:
            return String(localized: "Mirror")
        case .transparent:
            return String(localized: "Transparent")
        case .darkAbsorptive:
            return String(localized: "Dark / absorptive")
        case .occluded:
            return String(localized: "Occluded")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func constructionFeatureKindName(
        _ value: ConstructionFeatureKind
    ) -> String {
        switch value {
        case .riser:
            return String(localized: "Riser")
        case .stage:
            return String(localized: "Stage")
        case .soffit:
            return String(localized: "Soffit")
        case .beam:
            return String(localized: "Beam")
        case .partialHeightWall:
            return String(localized: "Partial-height wall")
        case .column:
            return String(localized: "Column")
        case .alcove:
            return String(localized: "Alcove")
        case .slopedCeiling:
            return String(localized: "Sloped ceiling")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func confirmationSourceName(
        _ value: SemanticConfirmationSource
    ) -> String {
        switch value {
        case .userConfirmed:
            return String(localized: "I confirmed this")
        case .captureAppSuggested:
            return String(localized: "App suggestion")
        case .importedReference:
            return String(localized: "Imported reference")
        }
    }

    public static func roomStateKindName(
        _ value: RoomStateKind
    ) -> String {
        switch value {
        case .curtain:
            return String(localized: "Curtain")
        case .movablePanel:
            return String(localized: "Movable panel")
        case .door:
            return String(localized: "Door")
        case .window:
            return String(localized: "Window")
        case .screenMasking:
            return String(localized: "Screen masking")
        case .seatPosture:
            return String(localized: "Seat posture")
        case .hvac:
            return String(localized: "HVAC")
        case .airPurifier:
            return String(localized: "Air purifier")
        case .lighting:
            return String(localized: "Lighting")
        case .removableElement:
            return String(localized: "Removable element")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func roomStateValueName(
        _ value: RoomStateValue
    ) -> String {
        switch value {
        case .open:
            return String(localized: "Open")
        case .closed:
            return String(localized: "Closed")
        case .deployed:
            return String(localized: "Deployed")
        case .stowed:
            return String(localized: "Stowed")
        case .on:
            return String(localized: "On")
        case .off:
            return String(localized: "Off")
        case .reclined:
            return String(localized: "Reclined")
        case .upright:
            return String(localized: "Upright")
        case .present:
            return String(localized: "Present")
        case .absent:
            return String(localized: "Absent")
        case .unknown:
            return String(localized: "Unknown")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func inventoryClassName(
        _ value: InventoryEquipmentClass
    ) -> String {
        switch value {
        case .avReceiver:
            return String(localized: "AV receiver")
        case .avProcessor:
            return String(localized: "AV processor")
        case .powerAmplifier:
            return String(localized: "Power amplifier")
        case .dspUnit:
            return String(localized: "DSP unit")
        case .projector:
            return String(localized: "Projector")
        case .display:
            return String(localized: "Display")
        case .sourceDevice:
            return String(localized: "Source device")
        case .measurementInterface:
            return String(localized: "Measurement interface")
        case .other:
            return String(localized: "Other")
        }
    }

    /// Rack-facing labels for placement observations (#402).
    public static func rackFacingName(
        _ value: RackFacing
    ) -> String {
        switch value {
        case .front:
            return String(localized: "Front")
        case .rear:
            return String(localized: "Rear")
        case .side:
            return String(localized: "Side")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    public static func furnitureCategoryName(
        _ value: FurnitureCategory
    ) -> String {
        switch value {
        case .table:
            return String(localized: "Table")
        case .sofa:
            return String(localized: "Sofa")
        case .chairRecliner:
            return String(localized: "Chair / recliner")
        case .cabinetStorage:
            return String(localized: "Cabinet / storage")
        case .equipmentFurniture:
            return String(localized: "Equipment furniture")
        case .other:
            return String(localized: "Other")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    public static func furnitureRelevanceName(
        _ value: FurnitureRelevance
    ) -> String {
        switch value {
        case .fixedBuiltIn:
            return String(localized: "Fixed / built-in")
        case .movable:
            return String(localized: "Movable")
        case .temporary:
            return String(localized: "Temporary")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    public static func mountingModeName(
        _ value: SpeakerMountingMode
    ) -> String {
        switch value {
        case .freestanding:
            return String(localized: "Freestanding")
        case .standMounted:
            return String(localized: "On a stand")
        case .onWall:
            return String(localized: "On wall")
        case .inWall:
            return String(localized: "In wall")
        case .inCeiling:
            return String(localized: "In ceiling")
        case .ceilingSurface:
            return String(localized: "Ceiling surface")
        case .baffleWall:
            return String(localized: "Baffle wall")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func transparencyName(
        _ value: AcousticTransparencyState
    ) -> String {
        switch value {
        case .transparent:
            return String(localized: "Acoustically transparent")
        case .opaque:
            return String(localized: "Acoustically opaque")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    public static func transparencySourceName(
        _ value: TransparencyAuthoritySource
    ) -> String {
        switch value {
        case .userAttestation:
            return String(localized: "My attestation")
        case .manufacturerSpecification:
            return String(localized: "Manufacturer specification")
        case .equipmentCatalog:
            return String(localized: "Equipment catalog")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func bandScopeName(
        _ value: RoutingBandScope
    ) -> String {
        switch value {
        case .fullRange:
            return String(localized: "Full range")
        case .highBandDirect:
            return String(localized: "High band direct")
        case .lowBandBassManaged:
            return String(localized: "Low band, bass-managed")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    public static func routingStateName(
        _ value: RoutingVerificationState
    ) -> String {
        switch value {
        case .verified:
            return String(localized: "Verified")
        case .manualLabel:
            return String(localized: "Label only")
        case .unknown:
            return String(localized: "Unknown")
        case .conflicting:
            return String(localized: "Conflicting")
        }
    }

    public static func routingMethodName(
        _ value: RoutingVerificationMethod
    ) -> String {
        switch value {
        case .userAttestation:
            return String(localized: "My attestation")
        case .cableLabelEvidence:
            return String(localized: "Cable label evidence")
        case .listenedTestSignal:
            return String(localized: "Listened to test signal")
        case .measuredSignalPath:
            return String(localized: "Measured signal path")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func mountOrientationName(
        _ value: ProjectorMountOrientation
    ) -> String {
        switch value {
        case .tabletopFront:
            return String(localized: "Tabletop, front projection")
        case .ceilingFront:
            return String(localized: "Ceiling, front projection")
        case .tabletopRear:
            return String(localized: "Tabletop, rear projection")
        case .ceilingRear:
            return String(localized: "Ceiling, rear projection")
        case .other:
            return String(localized: "Other")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    public static func focusStateName(
        _ value: ProjectorFocusState
    ) -> String {
        switch value {
        case .verified:
            return String(localized: "Verified")
        case .unverified:
            return String(localized: "Unverified")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    public static func guidanceModeName(
        _ value: AlignmentGuidanceMode
    ) -> String {
        switch value {
        case .spatialDelta:
            return String(localized: "Spatial delta")
        case .textualInstructions:
            return String(localized: "Written instructions")
        }
    }

    public static func alignmentMechanismName(
        _ value: PlanAlignmentMechanism
    ) -> String {
        switch value {
        case .roomReferenceFrame:
            return String(localized: "Room reference frame")
        case .referenceTarget:
            return String(localized: "Reference target")
        case .manualSurvey:
            return String(localized: "Manual survey")
        }
    }

    public static func precisionName(
        _ value: PrecisionSufficiency
    ) -> String {
        switch value {
        case .sufficient:
            return String(localized: "Sufficient")
        case .insufficient:
            return String(localized: "Insufficient")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    public static func semanticTaskKindName(
        _ value: SemanticTaskKind
    ) -> String {
        switch value {
        case .surfaceSemantics:
            return String(localized: "Surface type")
        case .surfaceConstruction:
            return String(localized: "Surface construction")
        case .problemSurface:
            return String(localized: "Problem surface")
        case .constructionFeature:
            return String(localized: "Room feature")
        case .roomStateObservation:
            return String(localized: "Room state observation")
        case .roomStateSnapshot:
            return String(localized: "Room state snapshot")
        case .inventoryItem:
            return String(localized: "Equipment item")
        case .furnitureSemantics:
            return String(localized: "Object identity")
        case .speakerInstallation:
            return String(localized: "Speaker installation")
        case .screenSemantics:
            return String(localized: "Screen semantics")
        case .seatLayout:
            return String(localized: "Seat layout")
        case .routingVerification:
            return String(localized: "Signal routing")
        case .projectorCommissioning:
            return String(localized: "Projector setup")
        case .installationAlignment:
            return String(localized: "Installation alignment")
        }
    }

    /// Human name for an annotation entity type — used anywhere a
    /// picker or row would otherwise render `type.rawValue`.
    public static func entityTypeName(
        _ value: AnnotationEntityType
    ) -> String {
        switch value {
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
            return String(localized: "Custom point")
        }
    }

    public static func openingKindName(
        _ value: RoomOpeningKind
    ) -> String {
        switch value {
        case .door:
            return String(localized: "Door")
        case .window:
            return String(localized: "Window")
        case .opening:
            return String(localized: "Opening")
        case .hvacGrille:
            return String(localized: "HVAC grille")
        case .transferGrille:
            return String(localized: "Transfer grille")
        case .doorUndercut:
            return String(localized: "Door undercut")
        case .servicePenetration:
            return String(localized: "Service penetration")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func openingStateName(
        _ value: RoomOpeningState
    ) -> String {
        switch value {
        case .open:
            return String(localized: "Open")
        case .closed:
            return String(localized: "Closed")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    /// Disposition names shared between the opening list and the plan
    /// legend (issue #367) — one localized vocabulary for both.
    public static func openingDispositionName(
        _ value: RoomOpeningDisposition
    ) -> String {
        switch value {
        case .unreviewed:
            return String(localized: "Pending review")
        case .confirmed:
            return String(localized: "Confirmed")
        case .needsMoreScanning:
            return String(localized: "Needs more scanning")
        case .intentionallyIgnored:
            return String(localized: "Intentionally ignored")
        }
    }

    public static func asBuiltStateName(
        _ value: AsBuiltItemState
    ) -> String {
        switch value {
        case .pending:
            return String(localized: "Pending")
        case .verified:
            return String(localized: "Verified")
        case .deviated:
            return String(localized: "Out of tolerance")
        case .captured:
            return String(localized: "Captured")
        case .indeterminate:
            return String(localized: "Indeterminate")
        case .unavailable:
            return String(localized: "Unavailable")
        }
    }

    /// Human retention label for evidence gallery rows (issue #367):
    /// the persisted `retention_reason` token stays in Details.
    public static func retentionReasonName(
        _ reason: EvidenceRetentionReason
    ) -> String {
        switch reason {
        case .endBoundary:
            return String(localized: "Kept as a scan-boundary frame")
        case .linkedToAuthority:
            return String(localized: "Linked to recorded details")
        case .automaticKeyframe:
            return String(localized: "Automatic keyframe")
        case .operatorSaved:
            return String(localized: "Saved during scan")
        }
    }

    /// Channel-role tokens (`L`, `SBL`, `LFE1`) read as acoustical
    /// labels; unrecognized custom tokens pass through unchanged —
    /// the token set is intentionally open (#244).
    public static func channelRoleName(
        _ value: ChannelRole
    ) -> String {
        switch value.rawValue {
        case "L": return String(localized: "Left")
        case "C": return String(localized: "Center")
        case "R": return String(localized: "Right")
        case "SL": return String(localized: "Surround left")
        case "SR": return String(localized: "Surround right")
        case "SBL": return String(localized: "Surround back left")
        case "SBR": return String(localized: "Surround back right")
        case "TFL": return String(localized: "Top front left")
        case "TFR": return String(localized: "Top front right")
        case "TML": return String(localized: "Top middle left")
        case "TMR": return String(localized: "Top middle right")
        case "TRL": return String(localized: "Top rear left")
        case "TRR": return String(localized: "Top rear right")
        case "LFE": return String(localized: "LFE")
        case "LFE1": return String(localized: "LFE 1")
        case "LFE2": return String(localized: "LFE 2")
        case "LFE3": return String(localized: "LFE 3")
        case "LFE4": return String(localized: "LFE 4")
        default: return value.rawValue
        }
    }

    /// How a field-evidence asset entered the capture (issue #367) —
    /// the record's `acquisition` token stays in the schema.
    public static func fieldEvidenceAcquisitionName(
        _ value: FieldEvidenceAcquisition
    ) -> String {
        switch value {
        case .linkedFrame:
            return String(localized: "Linked frame")
        case .capturedInApp:
            return String(localized: "Captured in app")
        case .importedFile:
            return String(localized: "Imported file")
        case .authoredNote:
            return String(localized: "Authored note")
        }
    }

    public static func datumOriginKindName(
        _ value: RoomFieldDatumOriginKind
    ) -> String {
        switch value {
        case .roomCorner:
            return String(localized: "Room corner")
        case .wallPoint:
            return String(localized: "Point on wall")
        case .surveyedPoint:
            return String(localized: "Surveyed point")
        case .screenPoint:
            return String(localized: "Screen point")
        case .roomFrameOrigin:
            return String(localized: "Room origin")
        }
    }

    public static func datumAxisKindName(
        _ value: RoomFieldDatumAxisKind
    ) -> String {
        switch value {
        case .twoSurveyedPoints:
            return String(localized: "Two surveyed points")
        case .wallDirection:
            return String(localized: "Wall direction")
        case .roomFrameFront:
            return String(localized: "Room front direction")
        case .screenDirection:
            return String(localized: "Screen direction")
        }
    }

    public static func datumVerticalKindName(
        _ value: RoomFieldDatumVerticalKind
    ) -> String {
        switch value {
        case .finishedFloor:
            return String(localized: "Finished floor")
        case .platformTop:
            return String(localized: "Platform top")
        }
    }

    /// Human subject for an evidence "referenced by" token (issue
    /// #367): entity labels, measurement types, opening kinds — the
    /// raw `entity:<id>` / `measurement:<id>` tokens stay under the
    /// technical detail.
    public static func referencedSubjectLabel(
        forRef ref: String,
        in model: CaptureReviewWorkspaceModel
    ) -> String {
        if let rest = ref.dropPrefix("entity:"),
           let entity = model.annotations.first(where: {
               $0.entityID.description == rest
           })
        {
            return entity.label.isEmpty
                ? String(localized: "An entity") : entity.label
        }
        if let rest = ref.dropPrefix("measurement:") {
            return model.measurements.first(where: {
                $0.measurementID.description == rest
            })?.quantityType
                ?? String(localized: "A measurement")
        }
        if let rest = ref.dropPrefix("opening:") {
            return model.openingReview?.openings.first(where: {
                $0.sourceRef == rest
            }).map { openingKindName($0.kind) }
                ?? String(localized: "An opening")
        }
        if let rest = ref.dropPrefix("field_evidence:") {
            return model.fieldEvidence.first(where: {
                $0.evidenceID.description == rest
            })?.title
                ?? String(localized: "Field evidence")
        }
        if ref == "room_frame" {
            return String(localized: "The room reference frame")
        }
        return ref
    }

    /// Marker-kind names shared by the plan legend (issue #367) — only
    /// classes actually present are listed.
    public static func planMarkerKindName(
        _ kind: RoomPlanPreviewModel.PlanMarker.Kind
    ) -> String {
        switch kind {
        case .door:
            return String(localized: "Door")
        case .window:
            return String(localized: "Window")
        case .opening:
            return String(localized: "Opening")
        case .object:
            return String(localized: "Object")
        case .annotation:
            return String(localized: "Annotation")
        case .roomFrameOrigin:
            return String(localized: "Room origin")
        case .roomFrameFront:
            return String(localized: "Room front direction")
        case .speaker:
            return String(localized: "Speaker")
        case .seat:
            return String(localized: "Seat")
        case .screen:
            return String(localized: "Screen")
        case .projector:
            return String(localized: "Projector")
        case .display:
            return String(localized: "Display")
        case .measurement:
            return String(localized: "Measurement point")
        case .referencePoint:
            return String(localized: "Reference point")
        case .genericEntity:
            return String(localized: "Entity")
        case .revisitFlag:
            return String(localized: "Revisit flag")
        }
    }
}

private extension String {
    /// Drops `prefix` when present, else nil — used to decode the
    /// `kind:id` tokens in evidence referencedBy lists.
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
