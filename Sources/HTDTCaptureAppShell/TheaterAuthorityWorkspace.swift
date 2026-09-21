import Foundation
import SwiftUI
import HTDTCaptureCore

/// A selectable captured element for the surface-binding pickers: a
/// RoomPlan surface/object or an ARMesh anchor, labelled for display.
public struct CapturedSurfaceOption: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case roomPlanSurface
        case roomPlanObject
        case meshAnchor
    }
    public let identifier: String
    public let kind: Kind
    public let label: String
    public var id: String { identifier }
    public init(identifier: String, kind: Kind, label: String) {
        self.identifier = identifier
        self.kind = kind
        self.label = label
    }
}

/// Theater-semantic authority sections (#218, #233, #256, #262, #264,
/// #280, #281, #288, #289, #290). Every record is user-authored
/// authority — the app never infers the semantics it records.
struct TheaterAuthoritySection: View {
    let coordinateSpaceID: CoordinateSpaceID
    /// Working revision identity — room-state snapshots bind it.
    let captureRevisionID: CaptureRevisionID
    let availableEvidenceRefs: [String]
    /// Staged annotation entities authority records may reference.
    let entities: [CaptureAnnotationEntity]
    /// Captured RoomPlan surfaces/objects offered for binding (#218).
    let roomPlanSurfaces: [CapturedSurfaceOption]
    /// Captured mesh anchors offered for binding (#218).
    let meshAnchors: [CapturedSurfaceOption]
    @Binding var authorities: TheaterAuthorityCollection

    @State private var addingKind: AuthorityKind?
    @State private var errorText: String?

    enum AuthorityKind: String, CaseIterable, Identifiable {
        case surfaceSemantics
        case surfaceConstruction
        case problemSurface
        case constructionFeature
        case roomStateObservation
        case roomStateSnapshot
        case inventoryItem
        case furnitureSemantics
        case speakerInstallation
        case screenSemantics
        case seatLayout

        var id: String { rawValue }

        var title: String {
            switch self {
            case .surfaceSemantics:
                return String(localized: "Surface authority")
            case .surfaceConstruction:
                return String(localized: "Construction observation")
            case .problemSurface:
                return String(localized: "Problem surface")
            case .constructionFeature:
                return String(localized: "Construction feature")
            case .roomStateObservation:
                return String(localized: "Room state observation")
            case .roomStateSnapshot:
                return String(localized: "Room state snapshot")
            case .inventoryItem:
                return String(localized: "Inventory item")
            case .furnitureSemantics:
                return String(localized: "Furniture confirmation")
            case .speakerInstallation:
                return String(localized: "Speaker installation")
            case .screenSemantics:
                return String(localized: "Screen semantics")
            case .seatLayout:
                return String(localized: "Seat layout")
            }
        }

        var count: (TheaterAuthorityCollection) -> Int {
            switch self {
            case .surfaceSemantics: return { $0.surfaceSemantics.count }
            case .surfaceConstruction:
                return { $0.surfaceConstructions.count }
            case .problemSurface: return { $0.problemSurfaces.count }
            case .constructionFeature:
                return { $0.constructionFeatures.count }
            case .roomStateObservation:
                return { $0.roomStateObservations.count }
            case .roomStateSnapshot:
                return { $0.roomStateSnapshots.count }
            case .inventoryItem: return { $0.inventoryItems.count }
            case .furnitureSemantics:
                return { $0.furnitureSemantics.count }
            case .speakerInstallation:
                return { $0.speakerInstallations.count }
            case .screenSemantics: return { $0.screenSemantics.count }
            case .seatLayout: return { $0.seatLayouts.count }
            }
        }
    }

    var body: some View {
        ForEach(AuthorityKind.allCases) { kind in
            LabeledContent(
                kind.title,
                value: String(kind.count(authorities))
            )
            Button(String(localized: "Add")) {
                addingKind = kind
            }
        }
        if let errorText {
            Text(errorText)
                .font(.caption)
                .foregroundStyle(.red)
        }
        Text(
            "Authorities are user-attested claims; the app never infers them. Records reference staged annotations above."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
            .sheet(item: $addingKind) { kind in
                addSheet(for: kind)
            }
    }

    func addSheet(for kind: AuthorityKind) -> some View {
        NavigationStack {
            AuthorityRecordForm(
                kind: kind,
                coordinateSpaceID: coordinateSpaceID,
                captureRevisionID: captureRevisionID,
                availableEvidenceRefs: availableEvidenceRefs,
                entities: entities,
                roomPlanSurfaces: roomPlanSurfaces,
                meshAnchors: meshAnchors,
                authorities: authorities
            ) { result in
                do {
                    authorities = try result.apply(to: authorities)
                    addingKind = nil
                    errorText = nil
                } catch {
                    errorText = String(describing: error)
                    addingKind = nil
                }
            }
        }
    }
}

/// The staged record produced by an add-sheet; `apply` rebuilds the
/// collection so cross-reference invariants stay centralized in the
/// model.
enum AuthorityRecordDraft {
    case surfaceSemantics(SurfaceSemanticAuthority)
    case surfaceConstruction(SurfaceConstructionObservation)
    case problemSurface(ProblemSurfaceObservation)
    case constructionFeature(ConstructionFeatureCandidate)
    case roomStateObservation(RoomStateObservation)
    case roomStateSnapshot(RoomStateSnapshot)
    case inventoryItem(SystemInventoryItem)
    case furnitureSemantics(FurnitureSemanticConfirmation)
    case speakerInstallation(SpeakerInstallationAuthority)
    case screenSemantics(ProjectionScreenSemantics)
    case seatLayout(SeatLayoutAuthority)

    func apply(
        to collection: TheaterAuthorityCollection
    ) throws -> TheaterAuthorityCollection {
        switch self {
        case .surfaceSemantics(let record):
            return try TheaterAuthorityCollection(
                surfaceSemantics:
                    collection.surfaceSemantics + [record],
                surfaceConstructions:
                    collection.surfaceConstructions,
                problemSurfaces: collection.problemSurfaces,
                constructionFeatures:
                    collection.constructionFeatures,
                roomStateObservations:
                    collection.roomStateObservations,
                roomStateSnapshots:
                    collection.roomStateSnapshots,
                inventoryItems: collection.inventoryItems,
                furnitureSemantics:
                    collection.furnitureSemantics,
                speakerInstallations:
                    collection.speakerInstallations,
                screenSemantics: collection.screenSemantics,
                seatLayouts: collection.seatLayouts
            )
        case .surfaceConstruction(let record):
            return try TheaterAuthorityCollection(
                surfaceSemantics: collection.surfaceSemantics,
                surfaceConstructions:
                    collection.surfaceConstructions + [record],
                problemSurfaces: collection.problemSurfaces,
                constructionFeatures:
                    collection.constructionFeatures,
                roomStateObservations:
                    collection.roomStateObservations,
                roomStateSnapshots:
                    collection.roomStateSnapshots,
                inventoryItems: collection.inventoryItems,
                furnitureSemantics:
                    collection.furnitureSemantics,
                speakerInstallations:
                    collection.speakerInstallations,
                screenSemantics: collection.screenSemantics,
                seatLayouts: collection.seatLayouts
            )
        case .problemSurface(let record):
            return try TheaterAuthorityCollection(
                surfaceSemantics: collection.surfaceSemantics,
                surfaceConstructions:
                    collection.surfaceConstructions,
                problemSurfaces:
                    collection.problemSurfaces + [record],
                constructionFeatures:
                    collection.constructionFeatures,
                roomStateObservations:
                    collection.roomStateObservations,
                roomStateSnapshots:
                    collection.roomStateSnapshots,
                inventoryItems: collection.inventoryItems,
                furnitureSemantics:
                    collection.furnitureSemantics,
                speakerInstallations:
                    collection.speakerInstallations,
                screenSemantics: collection.screenSemantics,
                seatLayouts: collection.seatLayouts
            )
        case .constructionFeature(let record):
            return try TheaterAuthorityCollection(
                surfaceSemantics: collection.surfaceSemantics,
                surfaceConstructions:
                    collection.surfaceConstructions,
                problemSurfaces: collection.problemSurfaces,
                constructionFeatures:
                    collection.constructionFeatures + [record],
                roomStateObservations:
                    collection.roomStateObservations,
                roomStateSnapshots:
                    collection.roomStateSnapshots,
                inventoryItems: collection.inventoryItems,
                furnitureSemantics:
                    collection.furnitureSemantics,
                speakerInstallations:
                    collection.speakerInstallations,
                screenSemantics: collection.screenSemantics,
                seatLayouts: collection.seatLayouts
            )
        case .roomStateObservation(let record):
            return try TheaterAuthorityCollection(
                surfaceSemantics: collection.surfaceSemantics,
                surfaceConstructions:
                    collection.surfaceConstructions,
                problemSurfaces: collection.problemSurfaces,
                constructionFeatures:
                    collection.constructionFeatures,
                roomStateObservations:
                    collection.roomStateObservations + [record],
                roomStateSnapshots:
                    collection.roomStateSnapshots,
                inventoryItems: collection.inventoryItems,
                furnitureSemantics:
                    collection.furnitureSemantics,
                speakerInstallations:
                    collection.speakerInstallations,
                screenSemantics: collection.screenSemantics,
                seatLayouts: collection.seatLayouts
            )
        case .roomStateSnapshot(let record):
            return try TheaterAuthorityCollection(
                surfaceSemantics: collection.surfaceSemantics,
                surfaceConstructions:
                    collection.surfaceConstructions,
                problemSurfaces: collection.problemSurfaces,
                constructionFeatures:
                    collection.constructionFeatures,
                roomStateObservations:
                    collection.roomStateObservations,
                roomStateSnapshots:
                    collection.roomStateSnapshots + [record],
                inventoryItems: collection.inventoryItems,
                furnitureSemantics:
                    collection.furnitureSemantics,
                speakerInstallations:
                    collection.speakerInstallations,
                screenSemantics: collection.screenSemantics,
                seatLayouts: collection.seatLayouts
            )
        case .inventoryItem(let record):
            return try TheaterAuthorityCollection(
                surfaceSemantics: collection.surfaceSemantics,
                surfaceConstructions:
                    collection.surfaceConstructions,
                problemSurfaces: collection.problemSurfaces,
                constructionFeatures:
                    collection.constructionFeatures,
                roomStateObservations:
                    collection.roomStateObservations,
                roomStateSnapshots:
                    collection.roomStateSnapshots,
                inventoryItems:
                    collection.inventoryItems + [record],
                furnitureSemantics:
                    collection.furnitureSemantics,
                speakerInstallations:
                    collection.speakerInstallations,
                screenSemantics: collection.screenSemantics,
                seatLayouts: collection.seatLayouts
            )
        case .furnitureSemantics(let record):
            return try TheaterAuthorityCollection(
                surfaceSemantics: collection.surfaceSemantics,
                surfaceConstructions:
                    collection.surfaceConstructions,
                problemSurfaces: collection.problemSurfaces,
                constructionFeatures:
                    collection.constructionFeatures,
                roomStateObservations:
                    collection.roomStateObservations,
                roomStateSnapshots:
                    collection.roomStateSnapshots,
                inventoryItems: collection.inventoryItems,
                furnitureSemantics:
                    collection.furnitureSemantics + [record],
                speakerInstallations:
                    collection.speakerInstallations,
                screenSemantics: collection.screenSemantics,
                seatLayouts: collection.seatLayouts
            )
        case .speakerInstallation(let record):
            return try TheaterAuthorityCollection(
                surfaceSemantics: collection.surfaceSemantics,
                surfaceConstructions:
                    collection.surfaceConstructions,
                problemSurfaces: collection.problemSurfaces,
                constructionFeatures:
                    collection.constructionFeatures,
                roomStateObservations:
                    collection.roomStateObservations,
                roomStateSnapshots:
                    collection.roomStateSnapshots,
                inventoryItems: collection.inventoryItems,
                furnitureSemantics:
                    collection.furnitureSemantics,
                speakerInstallations:
                    collection.speakerInstallations + [record],
                screenSemantics: collection.screenSemantics,
                seatLayouts: collection.seatLayouts
            )
        case .screenSemantics(let record):
            return try TheaterAuthorityCollection(
                surfaceSemantics: collection.surfaceSemantics,
                surfaceConstructions:
                    collection.surfaceConstructions,
                problemSurfaces: collection.problemSurfaces,
                constructionFeatures:
                    collection.constructionFeatures,
                roomStateObservations:
                    collection.roomStateObservations,
                roomStateSnapshots:
                    collection.roomStateSnapshots,
                inventoryItems: collection.inventoryItems,
                furnitureSemantics:
                    collection.furnitureSemantics,
                speakerInstallations:
                    collection.speakerInstallations,
                screenSemantics:
                    collection.screenSemantics + [record],
                seatLayouts: collection.seatLayouts
            )
        case .seatLayout(let record):
            return try TheaterAuthorityCollection(
                surfaceSemantics: collection.surfaceSemantics,
                surfaceConstructions:
                    collection.surfaceConstructions,
                problemSurfaces: collection.problemSurfaces,
                constructionFeatures:
                    collection.constructionFeatures,
                roomStateObservations:
                    collection.roomStateObservations,
                roomStateSnapshots:
                    collection.roomStateSnapshots,
                inventoryItems: collection.inventoryItems,
                furnitureSemantics:
                    collection.furnitureSemantics,
                speakerInstallations:
                    collection.speakerInstallations,
                screenSemantics: collection.screenSemantics,
                seatLayouts: collection.seatLayouts + [record]
            )
        }
    }
}

private func authorityUTCNow() -> String {
    BundleTimestamp.utcString(from: Date())
}

private func parsePolygonText(
    _ text: String
) throws -> [SpatialVector3F] {
    try text.split(whereSeparator: \.isNewline)
        .map(String.init)
        .map { line in
            let parts = line.split(separator: ",")
            guard parts.count == 3,
                  let x = Double(parts[0]
                        .trimmingCharacters(in: .whitespaces)),
                  let y = Double(parts[1]
                        .trimmingCharacters(in: .whitespaces)),
                  let z = Double(parts[2]
                        .trimmingCharacters(in: .whitespaces))
            else {
                throw TheaterAuthorityError.invalidPatchGeometry
            }
            return try SpatialVector3F(Float(x), Float(y), Float(z))
        }
}

private struct EntityPicker: View {
    let title: String
    let entities: [CaptureAnnotationEntity]
    let types: Set<AnnotationEntityType>
    @Binding var selection: AnnotationEntityID?

    var body: some View {
        let candidates = entities.filter {
            types.isEmpty || types.contains($0.type)
        }
        if candidates.isEmpty {
            LabeledContent(
                title,
                value: String(localized: "no matching annotation")
            )
            .foregroundStyle(.secondary)
        } else {
            Picker(title, selection: $selection) {
                Text(String(localized: "None"))
                    .tag(AnnotationEntityID?.none)
                ForEach(candidates, id: \.entityID) { entity in
                    Text(entity.label + " · " + entity.type.rawValue)
                        .tag(AnnotationEntityID?.some(entity.entityID))
                }
            }
        }
    }
}

/// One add-sheet per authority kind; all record validation lives in the
/// model initializers so the form stays a thin staging surface.
private struct AuthorityRecordForm: View {
    let kind: TheaterAuthoritySection.AuthorityKind
    let coordinateSpaceID: CoordinateSpaceID
    let captureRevisionID: CaptureRevisionID
    let availableEvidenceRefs: [String]
    let entities: [CaptureAnnotationEntity]
    let roomPlanSurfaces: [CapturedSurfaceOption]
    let meshAnchors: [CapturedSurfaceOption]
    let authorities: TheaterAuthorityCollection
    let onProduce: (AuthorityRecordDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    // Shared surface-binding fields (#218 family).
    @State private var roomPlanSurfaceID = ""
    @State private var roomPlanObjectID = ""
    @State private var meshAnchorText = ""
    @State private var roomPlanPick = ""
    @State private var meshAnchorPick = ""
    @State private var semanticEntityID = ""
    @State private var polygonText = ""
    @State private var evidenceSelection: Set<String> = []

    // Per-kind fields.
    @State private var label = ""
    @State private var notes = ""
    @State private var hostClassification:
        SurfaceHostClassification = .roomBoundary
    @State private var includeTreatment = false
    @State private var treatmentWidth = ""
    @State private var treatmentHeight = ""
    @State private var treatmentOffset = ""
    @State private var treatmentAirGap = ""
    @State private var constructionKind:
        SurfaceConstructionKind = .gypsumDrywall
    @State private var constructionSource:
        ConstructionObservationSource = .userObservation
    @State private var materialDetail = ""
    @State private var problemKind: ProblemSurfaceKind = .mirror
    @State private var featureKind:
        ConstructionFeatureKind = .riser
    @State private var confirmationSource:
        SemanticConfirmationSource = .userConfirmed
    @State private var roomStateKind:
        RoomStateKind = .curtain
    @State private var roomStateValue:
        RoomStateValue = .unknown
    @State private var stateDetail = ""
    @State private var targetEntitySelection:
        AnnotationEntityID?
    @State private var targetAuthoritySelection:
        AuthorityRecordID?
    @State private var snapshotObservations:
        Set<RoomStateObservationID> = []
    @State private var campaignID = ""
    @State private var inventoryClass:
        InventoryEquipmentClass = .avReceiver
    @State private var manufacturer = ""
    @State private var model = ""
    @State private var userLabel = ""
    @State private var serialNumber = ""
    @State private var hostRackSelection:
        AnnotationEntityID?
    @State private var includePosition = false
    @State private var posX = ""
    @State private var posY = ""
    @State private var posZ = ""
    @State private var includeEquipmentRef = false
    @State private var equipmentID = ""
    @State private var equipmentVersion = ""
    @State private var equipmentHash = ""
    @State private var furnitureCategory:
        FurnitureCategory = .table
    @State private var furnitureRelevance:
        FurnitureRelevance = .movable
    @State private var furnitureEntitySelection:
        AnnotationEntityID?
    @State private var furnitureUsesBinding = false
    @State private var mountingMode:
        SpeakerMountingMode = .freestanding
    @State private var speakerEntitySelection:
        AnnotationEntityID?
    @State private var includeHostSurface = false
    @State private var insertionDepth = ""
    @State private var hardwareNote = ""
    @State private var screenEntitySelection:
        AnnotationEntityID?
    @State private var apertureWidth = ""
    @State private var apertureHeight = ""
    @State private var frameWidth = ""
    @State private var frameHeight = ""
    @State private var transparency:
        AcousticTransparencyState = .unknown
    @State private var transparencySource:
        TransparencyAuthoritySource = .userAttestation
    @State private var maskingObservationSelection:
        RoomStateObservationID?
    @State private var behindScreenSpeakers:
        Set<AnnotationEntityID> = []
    @State private var seatEntitySelection:
        AnnotationEntityID?
    @State private var rowIdentifier = ""
    @State private var seatOrdinal = ""
    @State private var riserSelection: AuthorityRecordID?
    @State private var earEntitySelection: AnnotationEntityID?
    @State private var eyeEntitySelection: AnnotationEntityID?
    @State private var headObstructionHeight = ""
    @State private var headObstructionRadius = ""
    @State private var facingAzimuth = ""
    @State private var facingElevation = ""

    @State private var errorText: String?

    var body: some View {
        Form {
            if usesBinding {
                Section("Surface binding") {
                    if !roomPlanSurfaces.isEmpty {
                        Picker(
                            "Captured RoomPlan element",
                            selection: $roomPlanPick
                        ) {
                            Text(String(localized: "None"))
                                .tag("")
                            ForEach(roomPlanSurfaces) { option in
                                Text(option.label)
                                    .tag(option.identifier)
                            }
                        }
                        .onChange(of: roomPlanPick) { _, value in
                            guard
                                let option = roomPlanSurfaces
                                    .first(where: {
                                        $0.identifier == value
                                    })
                            else {
                                return
                            }
                            if option.kind == .roomPlanObject {
                                roomPlanObjectID = value
                            } else {
                                roomPlanSurfaceID = value
                            }
                        }
                    }
                    TextField(
                        "RoomPlan surface ID",
                        text: $roomPlanSurfaceID
                    )
                    TextField(
                        "RoomPlan object ID",
                        text: $roomPlanObjectID
                    )
                    if !meshAnchors.isEmpty {
                        Picker(
                            "Captured mesh anchor",
                            selection: $meshAnchorPick
                        ) {
                            Text(String(localized: "None"))
                                .tag("")
                            ForEach(meshAnchors) { option in
                                Text(option.label)
                                    .tag(option.identifier)
                            }
                        }
                        .onChange(of: meshAnchorPick) { _, value in
                            if !value.isEmpty {
                                meshAnchorText = value
                            }
                        }
                    }
                    TextField(
                        "Mesh anchor UUID",
                        text: $meshAnchorText
                    )
                    TextField(
                        "Semantic entity ID",
                        text: $semanticEntityID
                    )
                    TextField(
                        "Polygon outline, one x,y,z per line",
                        text: $polygonText,
                        axis: .vertical
                    )
                    Text(
                        "At least one lineage anchor is required: a RoomPlan ID, mesh anchor, semantic ID, or polygon."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            kindSections

            if usesEvidence,
               !availableEvidenceRefs.isEmpty
            {
                EvidenceReferenceSelector(
                    availableEvidenceRefs:
                        availableEvidenceRefs,
                    selectedEvidenceRefs: $evidenceSelection
                )
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(kind.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Add")) {
                    produce()
                }
            }
        }
    }

    private var usesBinding: Bool {
        switch kind {
        case .surfaceSemantics, .surfaceConstruction,
             .problemSurface, .constructionFeature:
            return true
        case .furnitureSemantics:
            return furnitureUsesBinding
        case .speakerInstallation:
            return includeHostSurface
        default:
            return false
        }
    }

    private var usesEvidence: Bool {
        switch kind {
        case .roomStateSnapshot:
            return false
        default:
            return true
        }
    }

    @ViewBuilder private var kindSections: some View {
        switch kind {
        case .surfaceSemantics:
            surfaceSemanticsSection
        case .surfaceConstruction:
            surfaceConstructionSection
        case .problemSurface:
            problemSurfaceSection
        case .constructionFeature:
            constructionFeatureSection
        case .roomStateObservation:
            roomStateObservationSection
        case .roomStateSnapshot:
            roomStateSnapshotSection
        case .inventoryItem:
            inventoryItemSection
        case .furnitureSemantics:
            furnitureSemanticsSection
        case .speakerInstallation:
            speakerInstallationSection
        case .screenSemantics:
            screenSemanticsSection
        case .seatLayout:
            seatLayoutSection
        }
    }

    private var surfaceSemanticsSection: some View {
        Group {
            Section("Surface authority") {
                TextField("Label", text: $label)
                Picker(
                    "Host classification",
                    selection: $hostClassification
                ) {
                    ForEach(
                        [
                            SurfaceHostClassification.roomBoundary,
                            .objectSurface,
                            .unknown,
                        ],
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }
            Section("Treatment placement") {
                Toggle(
                    "Attach treatment placement",
                    isOn: $includeTreatment
                )
                if includeTreatment {
                    TextField(
                        "Footprint width (m)",
                        text: $treatmentWidth
                    )
                    TextField(
                        "Footprint height (m)",
                        text: $treatmentHeight
                    )
                    TextField(
                        "Surface offset (m)",
                        text: $treatmentOffset
                    )
                    TextField(
                        "Air gap (m)",
                        text: $treatmentAirGap
                    )
                    TextField("Notes", text: $notes)
                    Text(
                        "Placement metadata only — no acoustic coefficients are synthesized."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var surfaceConstructionSection: some View {
        Section("Construction observation") {
            Picker(
                "Construction",
                selection: $constructionKind
            ) {
                ForEach(
                    SurfaceConstructionKind.allCases,
                    id: \.self
                ) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            TextField(
                "Material detail (optional)",
                text: $materialDetail
            )
            Picker("Source", selection: $constructionSource) {
                ForEach(
                    ConstructionObservationSource.allCases,
                    id: \.self
                ) { value in
                    Text(value.rawValue).tag(value)
                }
            }
        }
    }

    private var problemSurfaceSection: some View {
        Section("Problem surface") {
            Picker("Kind", selection: $problemKind) {
                ForEach(
                    ProblemSurfaceKind.allCases,
                    id: \.self
                ) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            TextField(
                "Notes (optional)",
                text: $notes
            )
        }
    }

    private var constructionFeatureSection: some View {
        Section("Construction feature") {
            Picker("Kind", selection: $featureKind) {
                ForEach(
                    ConstructionFeatureKind.allCases,
                    id: \.self
                ) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            Picker(
                "Confirmation",
                selection: $confirmationSource
            ) {
                ForEach(
                    SemanticConfirmationSource.allCases,
                    id: \.self
                ) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            TextField(
                "Label (optional)",
                text: $label
            )
        }
    }

    private var roomStateObservationSection: some View {
        Group {
            Section("Room state observation") {
                Picker("Kind", selection: $roomStateKind) {
                    ForEach(
                        RoomStateKind.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker("State", selection: $roomStateValue) {
                    ForEach(
                        RoomStateValue.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                TextField(
                    "State detail (optional)",
                    text: $stateDetail
                )
            }
            Section("Targets (optional)") {
                EntityPicker(
                    title: String(localized: "Entity"),
                    entities: entities,
                    types: [],
                    selection: $targetEntitySelection
                )
                Picker(
                    "Authority record",
                    selection: $targetAuthoritySelection
                ) {
                    Text(String(localized: "None"))
                        .tag(AuthorityRecordID?.none)
                    ForEach(
                        authorityRecordOptions,
                        id: \.id
                    ) { option in
                        Text(option.label)
                            .tag(
                                AuthorityRecordID?.some(option.id)
                            )
                    }
                }
            }
        }
    }

    private var roomStateSnapshotSection: some View {
        Group {
            Section("Snapshot") {
                TextField("Label", text: $label)
                TextField(
                    "Campaign ID (optional)",
                    text: $campaignID
                )
            }
            Section("Observations") {
                if authorities.roomStateObservations
                    .isEmpty
                {
                    Text(
                        "Add room state observations first; a snapshot binds an immutable set."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        authorities.roomStateObservations,
                        id: \.observationID
                    ) { observation in
                        Toggle(
                            isOn: Binding(
                                get: {
                                    snapshotObservations
                                        .contains(
                                            observation
                                                .observationID
                                        )
                                },
                                set: { on in
                                    if on {
                                        snapshotObservations
                                            .insert(
                                                observation
                                                    .observationID
                                            )
                                    } else {
                                        snapshotObservations
                                            .remove(
                                                observation
                                                    .observationID
                                            )
                                    }
                                }
                            )
                        ) {
                            Text(
                                observation.kind.rawValue
                                    + " · "
                                    + observation.state.rawValue
                            )
                        }
                    }
                }
            }
        }
    }

    private var inventoryItemSection: some View {
        Group {
            Section("Inventory item") {
                Picker(
                    "Class",
                    selection: $inventoryClass
                ) {
                    ForEach(
                        InventoryEquipmentClass.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                TextField(
                    "Label (required)",
                    text: $userLabel
                )
                TextField(
                    "Manufacturer (optional)",
                    text: $manufacturer
                )
                TextField(
                    "Model (optional)",
                    text: $model
                )
                TextField(
                    "Serial (optional)",
                    text: $serialNumber
                )
            }
            Section("Hosting") {
                EntityPicker(
                    title: String(localized: "Rack"),
                    entities: entities,
                    types: [.equipmentRack],
                    selection: $hostRackSelection
                )
                Toggle(
                    "Attach captured position",
                    isOn: $includePosition
                )
                if includePosition {
                    TextField("X (m)", text: $posX)
                    TextField("Y (m)", text: $posY)
                    TextField("Z (m)", text: $posZ)
                }
            }
            Section("Equipment authority") {
                Toggle(
                    "Attach equipment reference",
                    isOn: $includeEquipmentRef
                )
                if includeEquipmentRef {
                    TextField(
                        "Equipment ID",
                        text: $equipmentID
                    )
                    TextField(
                        "Equipment version",
                        text: $equipmentVersion
                    )
                    TextField(
                        "Equipment SHA-256",
                        text: $equipmentHash
                    )
                }
            }
        }
    }

    private var furnitureSemanticsSection: some View {
        Group {
            Section("Furniture confirmation") {
                EntityPicker(
                    title: String(localized: "Entity"),
                    entities: entities,
                    types: [],
                    selection: $furnitureEntitySelection
                )
                Toggle(
                    "Bind a surface instead/as well",
                    isOn: $furnitureUsesBinding
                )
                Picker(
                    "Category",
                    selection: $furnitureCategory
                ) {
                    ForEach(
                        FurnitureCategory.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker(
                    "Relevance",
                    selection: $furnitureRelevance
                ) {
                    ForEach(
                        FurnitureRelevance.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker(
                    "Confirmation",
                    selection: $confirmationSource
                ) {
                    ForEach(
                        SemanticConfirmationSource.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }
        }
    }

    private var speakerInstallationSection: some View {
        Group {
            Section("Speaker installation") {
                EntityPicker(
                    title: String(localized: "Speaker"),
                    entities: entities,
                    types: [.speaker, .subwoofer],
                    selection: $speakerEntitySelection
                )
                Picker(
                    "Mounting",
                    selection: $mountingMode
                ) {
                    ForEach(
                        SpeakerMountingMode.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                TextField(
                    "Insertion depth (m, optional)",
                    text: $insertionDepth
                )
                TextField(
                    "Hardware note (optional)",
                    text: $hardwareNote
                )
                Toggle(
                    "Bind host surface",
                    isOn: $includeHostSurface
                )
            }
        }
    }

    private var screenSemanticsSection: some View {
        Group {
            Section("Screen semantics") {
                EntityPicker(
                    title: String(localized: "Screen"),
                    entities: entities,
                    types: [.projectionScreen],
                    selection: $screenEntitySelection
                )
                Picker(
                    "Acoustically transparent",
                    selection: $transparency
                ) {
                    ForEach(
                        AcousticTransparencyState.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                if transparency != .unknown {
                    Picker(
                        "Transparency source",
                        selection: $transparencySource
                    ) {
                        ForEach(
                            TransparencyAuthoritySource
                                .allCases,
                            id: \.self
                        ) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                }
            }
            Section("Dimensions (m, optional)") {
                TextField(
                    "Visible aperture width",
                    text: $apertureWidth
                )
                TextField(
                    "Visible aperture height",
                    text: $apertureHeight
                )
                TextField(
                    "Outer frame width",
                    text: $frameWidth
                )
                TextField(
                    "Outer frame height",
                    text: $frameHeight
                )
            }
            Section("Relations") {
                Picker(
                    "Masking observation",
                    selection: $maskingObservationSelection
                ) {
                    Text(String(localized: "None"))
                        .tag(RoomStateObservationID?.none)
                    ForEach(
                        authorities.roomStateObservations
                            .filter {
                                $0.kind == .screenMasking
                            },
                        id: \.observationID
                    ) { observation in
                        Text(observation.state.rawValue)
                            .tag(
                                RoomStateObservationID?
                                    .some(observation.observationID)
                            )
                    }
                }
                ForEach(
                    entities.filter {
                        $0.type == .speaker
                            || $0.type == .subwoofer
                    },
                    id: \.entityID
                ) { entity in
                    Toggle(
                        isOn: Binding(
                            get: {
                                behindScreenSpeakers
                                    .contains(entity.entityID)
                            },
                            set: { on in
                                if on {
                                    behindScreenSpeakers
                                        .insert(entity.entityID)
                                } else {
                                    behindScreenSpeakers
                                        .remove(entity.entityID)
                                }
                            }
                        )
                    ) {
                        Text(entity.label)
                    }
                }
                Text(
                    "Toggle speakers mounted behind the screen."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var seatLayoutSection: some View {
        Group {
            Section("Seat layout") {
                EntityPicker(
                    title: String(localized: "Seat"),
                    entities: entities,
                    types: [.seat],
                    selection: $seatEntitySelection
                )
                TextField(
                    "Row identifier (optional)",
                    text: $rowIdentifier
                )
                TextField(
                    "Seat ordinal (optional)",
                    text: $seatOrdinal
                )
                Picker(
                    "Riser feature",
                    selection: $riserSelection
                ) {
                    Text(String(localized: "None"))
                        .tag(AuthorityRecordID?.none)
                    ForEach(
                        riserOptions,
                        id: \.id
                    ) { option in
                        Text(option.label)
                            .tag(
                                AuthorityRecordID?.some(option.id)
                            )
                    }
                }
            }
            Section("Listening linkage") {
                EntityPicker(
                    title: String(localized: "Ear position"),
                    entities: entities,
                    types: [.listeningPosition],
                    selection: $earEntitySelection
                )
                EntityPicker(
                    title: String(localized: "Eye reference"),
                    entities: entities,
                    types: [.referencePoint],
                    selection: $eyeEntitySelection
                )
                TextField(
                    "Facing azimuth deg (optional)",
                    text: $facingAzimuth
                )
                TextField(
                    "Facing elevation deg (optional)",
                    text: $facingElevation
                )
            }
            Section("Head obstruction (m, optional)") {
                TextField(
                    "Height",
                    text: $headObstructionHeight
                )
                TextField(
                    "Radius",
                    text: $headObstructionRadius
                )
            }
        }
    }

    private var authorityRecordOptions:
        [(id: AuthorityRecordID, label: String)]
    {
        func rows(
            _ records: [(AuthorityRecordID, String)]
        ) -> [(AuthorityRecordID, String)] {
            records
        }
        var options: [(AuthorityRecordID, String)] = []
        options += rows(
            authorities.surfaceSemantics.map {
                ($0.authorityID, "surface · " + ($0.label ?? ""))
            }
        )
        options += rows(
            authorities.surfaceConstructions.map {
                (
                    $0.authorityID,
                    "construction · "
                        + $0.constructionKind.rawValue
                )
            }
        )
        options += rows(
            authorities.problemSurfaces.map {
                ($0.authorityID, "problem · " + $0.kind.rawValue)
            }
        )
        options += rows(
            authorities.constructionFeatures.map {
                (
                    $0.authorityID,
                    "feature · " + $0.kind.rawValue
                )
            }
        )
        options += rows(
            authorities.inventoryItems.map {
                (
                    $0.itemID,
                    "inventory · " + $0.userLabel
                )
            }
        )
        options += rows(
            authorities.speakerInstallations.map {
                (
                    $0.authorityID,
                    "installation · "
                        + $0.mountingMode.rawValue
                )
            }
        )
        return options
    }

    private var riserOptions:
        [(id: AuthorityRecordID, label: String)]
    {
        authorities.constructionFeatures
            .filter { $0.kind == .riser || $0.kind == .stage }
            .map {
                (
                    $0.authorityID,
                    $0.kind.rawValue
                        + " · "
                        + ($0.label ?? "")
                )
            }
    }

    private func buildBinding() throws -> SurfaceRegionBinding? {
        guard usesBinding else {
            return nil
        }
        let meshAnchor: UUID? = try {
            let text = meshAnchorText.trimmingCharacters(
                in: .whitespaces
            )
            if text.isEmpty {
                return nil
            }
            guard let uuid = UUID(uuidString: text) else {
                throw TheaterAuthorityError
                    .invalidPatchGeometry
            }
            return uuid
        }()
        return try SurfaceRegionBinding(
            coordinateSpaceID: coordinateSpaceID,
            roomPlanSurfaceID:
                roomPlanSurfaceID.isEmpty
                    ? nil : roomPlanSurfaceID,
            roomPlanObjectID:
                roomPlanObjectID.isEmpty
                    ? nil : roomPlanObjectID,
            meshAnchorID: meshAnchor,
            semanticEntityID:
                semanticEntityID.isEmpty
                    ? nil : semanticEntityID,
            polygonWorld: try parsePolygonText(polygonText),
            evidenceRefs: evidenceSelection.sorted()
        )
    }

    private func optionalMeters(
        _ text: String
    ) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let value = Double(trimmed), value.isFinite
        else {
            throw TheaterAuthorityError.invalidPatchGeometry
        }
        return value
    }

    private func equipmentReference() throws
        -> HTDTEquipmentReference?
    {
        guard includeEquipmentRef else {
            return nil
        }
        return try HTDTEquipmentReference(
            equipmentID: equipmentID,
            equipmentVersion: equipmentVersion,
            equipmentHash: try EvidenceSHA256(
                equipmentHash
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
            )
        )
    }

    private func produce() {
        do {
            let binding = try buildBinding()
            let draft: AuthorityRecordDraft
            switch kind {
            case .surfaceSemantics:
                draft = .surfaceSemantics(
                    try SurfaceSemanticAuthority(
                        label: label.isEmpty ? nil : label,
                        binding: binding!,
                        hostClassification:
                            hostClassification,
                        treatment:
                            try includeTreatment
                            ? TreatmentPlacementAuthority(
                                footprintWidthMeters:
                                    optionalMeters(
                                        treatmentWidth
                                    ),
                                footprintHeightMeters:
                                    optionalMeters(
                                        treatmentHeight
                                    ),
                                surfaceOffsetMeters:
                                    optionalMeters(
                                        treatmentOffset
                                    ),
                                airGapMeters:
                                    optionalMeters(
                                        treatmentAirGap
                                    ),
                                notes:
                                    notes.isEmpty
                                        ? nil : notes
                            )
                            : nil
                    )
                )
            case .surfaceConstruction:
                draft = .surfaceConstruction(
                    try SurfaceConstructionObservation(
                        binding: binding!,
                        constructionKind: constructionKind,
                        materialDetail:
                            materialDetail.isEmpty
                                ? nil : materialDetail,
                        source: constructionSource
                    )
                )
            case .problemSurface:
                draft = .problemSurface(
                    try ProblemSurfaceObservation(
                        binding: binding!,
                        kind: problemKind,
                        notes: notes.isEmpty ? nil : notes
                    )
                )
            case .constructionFeature:
                draft = .constructionFeature(
                    try ConstructionFeatureCandidate(
                        binding: binding!,
                        kind: featureKind,
                        confirmationSource:
                            confirmationSource,
                        label: label.isEmpty ? nil : label
                    )
                )
            case .roomStateObservation:
                draft = .roomStateObservation(
                    try RoomStateObservation(
                        kind: roomStateKind,
                        state: roomStateValue,
                        stateDetail:
                            stateDetail.isEmpty
                                ? nil : stateDetail,
                        targetEntityID:
                            targetEntitySelection,
                        targetAuthorityID:
                            targetAuthoritySelection,
                        coordinateSpaceID:
                            evidenceSelection.isEmpty
                                ? nil : coordinateSpaceID,
                        observedAtUTC: authorityUTCNow(),
                        evidenceRefs:
                            evidenceSelection.sorted()
                    )
                )
            case .roomStateSnapshot:
                let selected =
                    authorities.roomStateObservations
                        .filter {
                            snapshotObservations
                                .contains($0.observationID)
                        }
                draft = .roomStateSnapshot(
                    try TheaterAuthorityBuilder
                        .roomStateSnapshot(
                            label: label,
                            captureRevisionID:
                                captureRevisionID,
                            observedAtUTC:
                                authorityUTCNow(),
                            observations: selected,
                            campaignID:
                                campaignID.isEmpty
                                    ? nil : campaignID
                        )
                )
            case .inventoryItem:
                var transform: Matrix4x4F?
                var itemSpace: CoordinateSpaceID?
                if includePosition {
                    guard let x = Double(posX),
                          let y = Double(posY),
                          let z = Double(posZ)
                    else {
                        throw ManualAuthorityBuilderError
                            .invalidPosition
                    }
                    transform = try Matrix4x4F(values: [
                        1, 0, 0, 0,
                        0, 1, 0, 0,
                        0, 0, 1, 0,
                        Float(x), Float(y), Float(z), 1,
                    ])
                    itemSpace = coordinateSpaceID
                }
                draft = .inventoryItem(
                    try SystemInventoryItem(
                        equipmentClass: inventoryClass,
                        manufacturer:
                            manufacturer.isEmpty
                                ? nil : manufacturer,
                        model: model.isEmpty ? nil : model,
                        userLabel: userLabel,
                        equipmentRef:
                            try equipmentReference(),
                        serialNumber:
                            serialNumber.isEmpty
                                ? nil : serialNumber,
                        hostRackEntityID: hostRackSelection,
                        coordinateSpaceID: itemSpace,
                        worldFromItem: transform,
                        evidenceRefs:
                            evidenceSelection.sorted()
                    )
                )
            case .furnitureSemantics:
                draft = .furnitureSemantics(
                    try FurnitureSemanticConfirmation(
                        targetEntityID:
                            furnitureEntitySelection,
                        binding: binding,
                        category: furnitureCategory,
                        relevance: furnitureRelevance,
                        source: confirmationSource
                    )
                )
            case .speakerInstallation:
                guard let speakerEntitySelection else {
                    errorText = String(
                        localized:
                            "Add a speaker annotation first."
                    )
                    return
                }
                draft = .speakerInstallation(
                    try SpeakerInstallationAuthority(
                        speakerEntityID:
                            speakerEntitySelection,
                        mountingMode: mountingMode,
                        hostSurface: binding,
                        insertionDepthMeters:
                            try optionalMeters(
                                insertionDepth
                            ),
                        hardwareNote:
                            hardwareNote.isEmpty
                                ? nil : hardwareNote
                    )
                )
            case .screenSemantics:
                guard let screenEntitySelection else {
                    errorText = String(
                        localized:
                            "Add a projection screen annotation first."
                    )
                    return
                }
                draft = .screenSemantics(
                    try ProjectionScreenSemantics(
                        screenEntityID:
                            screenEntitySelection,
                        visibleApertureWidthMeters:
                            try optionalMeters(
                                apertureWidth
                            ),
                        visibleApertureHeightMeters:
                            try optionalMeters(
                                apertureHeight
                            ),
                        frameWidthMeters:
                            try optionalMeters(frameWidth),
                        frameHeightMeters:
                            try optionalMeters(
                                frameHeight
                            ),
                        acousticallyTransparent:
                            transparency,
                        transparencySource:
                            transparency == .unknown
                                ? nil : transparencySource,
                        maskingObservationID:
                            maskingObservationSelection,
                        behindScreenSpeakerEntityIDs:
                            behindScreenSpeakers
                                .sorted {
                                    $0.description
                                        < $1.description
                                }
                    )
                )
            case .seatLayout:
                guard let seatEntitySelection else {
                    errorText = String(
                        localized:
                            "Add a seat annotation first."
                    )
                    return
                }
                var facing: OrientationAxes?
                if !facingAzimuth.isEmpty {
                    facing = try ManualAuthorityBuilder
                        .speakerOrientationAxes(
                            azimuthDegrees:
                                Double(facingAzimuth),
                            elevationDegrees:
                                facingElevation.isEmpty
                                    ? nil
                                    : Double(facingElevation)
                        )
                }
                draft = .seatLayout(
                    try SeatLayoutAuthority(
                        seatEntityID: seatEntitySelection,
                        rowIdentifier:
                            rowIdentifier.isEmpty
                                ? nil : rowIdentifier,
                        seatOrdinal:
                            seatOrdinal.isEmpty
                                ? nil : Int(seatOrdinal),
                        riserAuthorityID: riserSelection,
                        earListeningEntityID:
                            earEntitySelection,
                        eyeReferenceEntityID:
                            eyeEntitySelection,
                        headObstructionHeightMeters:
                            try optionalMeters(
                                headObstructionHeight
                            ),
                        headObstructionRadiusMeters:
                            try optionalMeters(
                                headObstructionRadius
                            ),
                        facingOrientation: facing
                    )
                )
            }
            onProduce(draft)
        } catch {
            errorText = String(describing: error)
        }
    }
}
