import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore

/// Task-oriented annotation form (#220) used for both adding a new
/// entity and editing a staged one (#245 — the entity's `entityID` and
/// untouched fields survive the edit). The primary path exposes home-
/// theater tasks — templates, typed channel roles, camera-first
/// placement and heading — while raw schema controls live under an
/// explicit Advanced section.
public struct AnnotationEntityForm: View {
    /// nil for a new annotation; an existing entity for edit mode.
    private let editingEntity: CaptureAnnotationEntity?
    private let editingIdentityRecord: EquipmentIdentityRecord?

    public let coordinateSpaceID: CoordinateSpaceID
    public let evidenceFrames: [EvidenceFramePresentation]
    /// Refs with no decodable presentation (non-frame refs) still
    /// render as text rows.
    public let otherEvidenceRefs: [String]
    public let equipmentCatalogEntries: [HTDTEquipmentCatalogEntry]
    public let equipmentRecents: EquipmentRecents
    public let roomPlanObjects: [RoomPlanBindableObject]
    /// Shared AR preview for the camera sheets; nil disables camera
    /// capture controls (they stay visible but report unavailable).
    public let cameraPreview: AnyView?
    /// Spatial authority sealed for finalization (#276): camera
    /// placement/orientation capture can no longer write live spatial
    /// evidence, so the camera affordances hide like `cameraPreview`
    /// being nil. Semantic edits stay open.
    public let spatialCaptureSealed: Bool
    public let probePlacementTarget:
        () async -> AnnotationPlacementProbe
    public let probeCameraHeading: () async -> Float?
    public let captureTargetedPlacement: (
        PlacementTargetPreference
    ) async throws -> AnnotationPlacementAuthority?
    public let captureSpeakerOrientation:
        () async throws -> AnnotationOrientationAuthority
    /// Full-3D orientation capture for measurement-point direction
    /// authority (issue #271); distinct from the horizontal-heading
    /// `captureSpeakerOrientation` convention.
    public let capturePointOrientation:
        () async throws -> AnnotationOrientationAuthority
    /// Captures a plain evidence frame for equipment identity photos
    /// (#239); returns its canonical `path:` ref.
    public let captureIdentityPhoto: () async throws -> String
    /// Versioned layout profile this form binds speaker roles to
    /// (#315). When non-nil the speaker/subwoofer role picker offers
    /// the profile's logical role IDs and the saved entity records a
    /// `role_binding`; nil keeps the legacy free-token behavior.
    public let layoutProfile: SpeakerLayoutProfile?
    /// Label-scan assist (#345): captures a close-up label frame,
    /// runs OCR/barcode recognition, and returns suggestion
    /// candidates for the operator to confirm. Nil hides the control;
    /// a result never commits fields by itself.
    public let scanEquipmentLabel:
        (() async throws -> EquipmentLabelScanResult)?
    /// Delivers the built entity plus its optional equipment-identity
    /// attestation.
    public let onSave: (
        CaptureAnnotationEntity,
        EquipmentIdentityRecord?
    ) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var seed: AnnotationEditSeed
    @State private var type: AnnotationEntityType
    @State private var label: String
    @State private var channelRole: ChannelRole?
    @State private var customRoleText = ""

    // Position: either a captured authority or manual XYZ.
    @State private var placementAuthority:
        AnnotationPlacementAuthority?
    @State private var xText = "0"
    @State private var yText = "0"
    @State private var zText = "0"
    @State private var positionEdited = false

    // Orientation: captured heading or manual yaw. Only meaningful
    // on types with body/plane semantics.
    @State private var orientationAuthority:
        AnnotationOrientationAuthority?
    @State private var yawText = ""
    @State private var yawEdited = false
    // Speaker aim pitch (#228): tilted/Atmos speakers record
    // elevation alongside azimuth.
    @State private var elevationText = ""
    @State private var elevationEdited = false

    // Contract detail fields: typed listening role (#243), explicit
    // reference-point semantics/construction (#291), optional
    // physical envelope (#230).
    @State private var listeningRole: ListeningPositionRole
    @State private var semanticsSelection: String
    @State private var referencePointConstruction:
        ReferencePointConstruction = .surfaceHitConfirmed
    @State private var offsetXText = "0"
    @State private var offsetYText = "0"
    @State private var offsetZText = "0"
    @State private var envelopeWidthText = ""
    @State private var envelopeHeightText = ""
    @State private var envelopeDepthText = ""

    @State private var includeEquipmentReference = false
    @State private var selectedEquipmentKey = ""
    @State private var equipmentID = ""
    @State private var equipmentVersion = ""
    @State private var equipmentHash = ""
    @State private var equipmentAuthorityVersion: String?

    // Equipment identity evidence (#239).
    @State private var identityEvidenceRefs: [String] = []
    @State private var serialText = ""
    @State private var attestedPhysicalMatch = false
    @State private var capturingIdentityPhoto = false

    @State private var evidenceSelection =
        AnnotationEvidenceSelection()
    @State private var showingCameraSheet = false
    @State private var cameraMode: AnnotationCameraCaptureMode =
        .position
    @State private var showingCatalogPicker = false
    @State private var showingAdvanced = false
    @State private var errorText: String?
    @State private var capturingPointDirection = false
    // Profile role binding (#315): the logical role ID selected in
    // the active profile; "" means unbound/legacy channel token.
    @State private var selectedRoleBindingID: String
    // Label-scan assist (#345).
    @State private var scanningLabel = false
    @State private var scanResult: EquipmentLabelScanResult?
    @State private var labelScanProvenance:
        EquipmentLabelScanProvenance?

    public init(
        editingEntity: CaptureAnnotationEntity? = nil,
        editingIdentityRecord: EquipmentIdentityRecord? = nil,
        coordinateSpaceID: CoordinateSpaceID,
        evidenceFrames: [EvidenceFramePresentation] = [],
        otherEvidenceRefs: [String] = [],
        equipmentCatalogEntries: [HTDTEquipmentCatalogEntry] = [],
        equipmentRecents: EquipmentRecents = EquipmentRecents(),
        roomPlanObjects: [RoomPlanBindableObject] = [],
        cameraPreview: AnyView? = nil,
        spatialCaptureSealed: Bool = false,
        probePlacementTarget: @escaping
            () async -> AnnotationPlacementProbe =
            { .unavailable },
        probeCameraHeading: @escaping
            () async -> Float? = { nil },
        captureTargetedPlacement: @escaping (
            PlacementTargetPreference
        ) async throws -> AnnotationPlacementAuthority? = { _ in nil },
        captureSpeakerOrientation: @escaping
            () async throws -> AnnotationOrientationAuthority = {
                throw ManualAuthorityBuilderError.invalidSpeakerYaw
            },
        capturePointOrientation: @escaping
            () async throws -> AnnotationOrientationAuthority = {
                throw ManualAuthorityBuilderError
                    .pointDirectionUnavailable
            },
        captureIdentityPhoto: @escaping
            () async throws -> String = {
                throw ManualAuthorityBuilderError.invalidPosition
            },
        layoutProfile: SpeakerLayoutProfile? = nil,
        scanEquipmentLabel:
            (() async throws -> EquipmentLabelScanResult)? = nil,
        onSave: @escaping (
            CaptureAnnotationEntity,
            EquipmentIdentityRecord?
        ) -> Void
    ) {
        self.editingEntity = editingEntity
        self.editingIdentityRecord = editingIdentityRecord
        self.coordinateSpaceID = coordinateSpaceID
        self.evidenceFrames = evidenceFrames
        self.otherEvidenceRefs = otherEvidenceRefs
        self.equipmentCatalogEntries = equipmentCatalogEntries
        self.equipmentRecents = equipmentRecents
        self.roomPlanObjects = roomPlanObjects
        self.cameraPreview = cameraPreview
        self.spatialCaptureSealed = spatialCaptureSealed
        self.probePlacementTarget = probePlacementTarget
        self.probeCameraHeading = probeCameraHeading
        self.captureTargetedPlacement = captureTargetedPlacement
        self.captureSpeakerOrientation = captureSpeakerOrientation
        self.capturePointOrientation = capturePointOrientation
        self.captureIdentityPhoto = captureIdentityPhoto
        self.layoutProfile = layoutProfile
        self.scanEquipmentLabel = scanEquipmentLabel
        self.onSave = onSave

        let seed = editingEntity.map(AnnotationEditSeed.init(entity:))
            ?? AnnotationEditSeed(
                freshType: .listeningPosition
            )
        _seed = State(initialValue: seed)
        let initialType =
            editingEntity?.type ?? .listeningPosition
        _type = State(initialValue: initialType)
        _label = State(
            initialValue: editingEntity?.label
                ?? AnnotationPresentation
                    .defaultLabel(for: initialType)
        )
        _channelRole = State(initialValue: seed.channelRole)
        _customRoleText = State(
            initialValue: seed.channelRole
                .map { $0.isStandardRole ? "" : $0.rawValue }
                ?? ""
        )
        _listeningRole = State(
            initialValue:
                editingEntity?.listeningRole ?? .primary
        )
        _semanticsSelection = State(
            initialValue:
                editingEntity?.referencePointSemantics.rawValue ?? ""
        )
        _referencePointConstruction = State(
            initialValue: editingEntity?.referencePoint?.construction
                ?? .surfaceHitConfirmed
        )
        let originalOffset =
            editingEntity?.referencePoint?.offsetMeters
        _offsetXText = State(
            initialValue: originalOffset.map {
                Self.coordText($0.x)
            } ?? "0"
        )
        _offsetYText = State(
            initialValue: originalOffset.map {
                Self.coordText($0.y)
            } ?? "0"
        )
        _offsetZText = State(
            initialValue: originalOffset.map {
                Self.coordText($0.z)
            } ?? "0"
        )
        _envelopeWidthText = State(
            initialValue:
                editingEntity?.physicalEnvelope?.widthMeters
                    .map { Self.coordText(Float($0)) } ?? ""
        )
        _envelopeHeightText = State(
            initialValue:
                editingEntity?.physicalEnvelope?.heightMeters
                    .map { Self.coordText(Float($0)) } ?? ""
        )
        _envelopeDepthText = State(
            initialValue:
                editingEntity?.physicalEnvelope?.depthMeters
                    .map { Self.coordText(Float($0)) } ?? ""
        )
        _xText = State(
            initialValue: Self.coordText(seed.positionMeters.x)
        )
        _yText = State(
            initialValue: Self.coordText(seed.positionMeters.y)
        )
        _zText = State(
            initialValue: Self.coordText(seed.positionMeters.z)
        )
        _positionEdited = State(initialValue: false)
        // #228: a fresh speaker starts aim-unset — an entered yaw
        // (or a captured heading) produces the aim; nothing
        // fabricates one. Other types keep the legacy 0° default.
        _yawText = State(
            initialValue: seed.yawDegrees.map {
                String(format: "%.0f", Double($0))
            } ?? (seed.type == .speaker ? "" : "0")
        )
        _elevationText = State(
            initialValue: seed.elevationDegrees.map {
                String(format: "%.0f", Double($0))
            } ?? ""
        )
        _includeEquipmentReference = State(
            initialValue: seed.equipmentRef != nil
        )
        _equipmentID = State(
            initialValue: seed.equipmentRef?.equipmentID ?? ""
        )
        _equipmentVersion = State(
            initialValue: seed.equipmentRef?.equipmentVersion ?? ""
        )
        _equipmentHash = State(
            initialValue: seed.equipmentRef?.equipmentHash
                .description ?? ""
        )
        _equipmentAuthorityVersion = State(
            initialValue: seed.equipmentRef?.authorityVersion
        )
        _selectedEquipmentKey = State(
            initialValue: equipmentCatalogEntries.first(where: {
                entry in
                guard let ref = seed.equipmentRef else { return false }
                return entry.definitionID == ref.equipmentID
                    && entry.version == ref.equipmentVersion
                    && entry.semanticSHA256 == ref.equipmentHash
            })?.selectionKey ?? ""
        )
        _identityEvidenceRefs = State(
            initialValue:
                editingIdentityRecord?.identityEvidenceRefs ?? []
        )
        _serialText = State(
            initialValue:
                editingIdentityRecord?.serialOrAssetTag ?? ""
        )
        _attestedPhysicalMatch = State(
            initialValue:
                editingIdentityRecord?.attestedPhysicalMatch ?? false
        )
        _selectedRoleBindingID = State(
            initialValue:
                editingEntity?.roleBinding?.roleID ?? ""
        )
        _labelScanProvenance = State(
            initialValue: editingIdentityRecord?.labelScan
        )
        // Preserve every ref the entity already carries as a user
        // selection so an edit never silently drops evidence; fresh
        // captures add their authority-owned refs on top (#245).
        _evidenceSelection = State(
            initialValue: AnnotationEvidenceSelection(
                userSelected: Set(editingEntity?.evidenceRefs ?? [])
            )
        )
    }

    private var isEditing: Bool { editingEntity != nil }

    private var isSpeakerLike: Bool {
        type == .speaker || type == .subwoofer
    }

    /// The current HTDT catalog's acoustic-source authority only
    /// covers speaker/subwoofer annotations (#237); other types never
    /// see the equipment picker.
    private var equipmentCompatible: Bool {
        HTDTEquipmentCompatibility.compatibleTypes(
            authorityVersion: HTDTEquipmentCatalogSnapshot
                .expectedAuthorityVersion
        )?.contains(type) ?? false
    }

    /// Constructions valid for the currently captured placement
    /// method (#291): mesh/raycast hits are surface-derived; a
    /// RoomPlan object binding is a direct placement.
    private var availableConstructions: [ReferencePointConstruction] {
        guard let placementAuthority else { return [] }
        let surfaceDerived =
            placementAuthority.placement.method == .raycast
            || placementAuthority.placement.method == .meshHitTest
        return surfaceDerived
            ? [.surfaceHitConfirmed, .offsetFromSurface]
            : [.directPlacement]
    }

    public var body: some View {
        Form {
            Section(
                String(localized: "What are you adding?")
            ) {
                Picker(
                    String(localized: "Item"),
                    selection: $type
                ) {
                    ForEach(
                        AnnotationPresentation.entityTemplates,
                        id: \.self
                    ) { value in
                        DescribedPickerOption(
                            title: AnnotationPresentation
                                .entityTypeName(value),
                            detail: AnnotationPresentation
                                .entityTypeDescription(value)
                        )
                        .tag(value)
                    }
                }
                .onChange(of: type) { _, newType in
                    // Keep a deliberate label; refresh only untouched
                    // or template-default labels.
                    if label.isEmpty
                        || AnnotationPresentation.entityTemplates
                            .map(AnnotationPresentation.defaultLabel)
                            .contains(label)
                    {
                        label = AnnotationPresentation
                            .defaultLabel(for: newType)
                    }
                    channelRole =
                        newType == .subwoofer ? .lfe1
                        : newType == .speaker ? .left
                        : nil
                    customRoleText = ""
                    // Profile-bound role pick (#315): default to the
                    // profile's first matching logical role so a fresh
                    // speaker starts bound, never free-token.
                    if let layoutProfile,
                       newType == .speaker || newType == .subwoofer
                    {
                        selectedRoleBindingID =
                            layoutProfile.roles.first(where: {
                                $0.isSubwoofer
                                    == (newType == .subwoofer)
                            })?.roleID ?? ""
                        if let definition = layoutProfile
                            .roleDefinition(
                                roleID: selectedRoleBindingID
                            )
                        {
                            channelRole = definition.channelRole
                        }
                    } else {
                        selectedRoleBindingID = ""
                    }
                    semanticsSelection = ""
                    if !newType.supportsOrientationAuthority {
                        orientationAuthority = nil
                        evidenceSelection
                            .replaceOrientationAuthority(nil)
                        yawText = ""
                    }
                    if !equipmentCompatible {
                        includeEquipmentReference = false
                        selectedEquipmentKey = ""
                    }
                }
                TextField(
                    String(localized: "Label"),
                    text: $label
                )
            }

            positionSection

            if type == .listeningPosition {
                Section(String(localized: "Listening position role")) {
                    Picker(
                        String(localized: "Role"),
                        selection: $listeningRole
                    ) {
                        ForEach(
                            ListeningPositionRole.allCases,
                            id: \.self
                        ) { role in
                            DescribedPickerOption(
                                title: AnnotationPresentation
                                    .listeningRoleName(role),
                                detail: AnnotationPresentation
                                    .listeningRoleDescription(role)
                            )
                            .tag(role)
                        }
                    }
                    Text(
                        "The role is machine-readable; the label stays a free human name. Exactly one primary MLP is expected per layout."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if placementAuthority != nil {
                referencePointSection
            }

            if let semantics = type.allowedReferenceSemantics,
               semantics.count > 1
            {
                Section(
                    String(localized: "Reference point semantics")
                ) {
                    Picker(
                        String(localized: "Semantics"),
                        selection: $semanticsSelection
                    ) {
                        DescribedPickerOption(
                            title: String(localized: "Type default"),
                            detail: String(localized:
                                "Use the semantics the item type normally implies.")
                        )
                        .tag("")
                        ForEach(
                            semantics.sorted {
                                $0.rawValue < $1.rawValue
                            },
                            id: \.self
                        ) { token in
                            DescribedPickerOption(
                                title: MissionPresentation
                                    .referencePointSemanticsName(token),
                                detail: MissionPresentation
                                    .referencePointSemanticsDescription(
                                        token
                                    )
                            ).tag(token.rawValue)
                        }
                    }
                }
            }

            if type.supportsOrientationAuthority {
                orientationSection
            }

            if type == .measurementPoint {
                pointDirectionSection
            }

            if type != .listeningPosition
                && type != .referencePoint
            {
                Section(
                    String(localized: "Physical envelope (m, optional)")
                ) {
                    TextField(
                        String(localized: "Width"),
                        text: $envelopeWidthText
                    )
                    .decimalKeyboard()
                    TextField(
                        String(localized: "Height"),
                        text: $envelopeHeightText
                    )
                    .decimalKeyboard()
                    TextField(
                        String(localized: "Depth (m)"),
                        text: $envelopeDepthText
                    )
                    .decimalKeyboard()
                    Text(
                        "Dimensions are stored with user_measured provenance. Leave blank when unknown — nothing is inferred."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if equipmentCompatible {
                equipmentSection
            }

            if !evidenceFrames.isEmpty || !otherEvidenceRefs.isEmpty {
                EvidenceFramePickerView(
                    frames: evidenceFrames,
                    remainingRefs: otherEvidenceRefs,
                    selectedRefs: $evidenceSelection.userSelected
                )
            }

            advancedSection

            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(CaptureColorRole.blocked.color)
                }
            }
        }
        .navigationTitle(
            isEditing
                ? String(localized: "Edit annotation")
                : String(localized: "Add annotation")
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(
                    isEditing
                        ? String(localized: "Save")
                        : String(localized: "Add")
                ) {
                    save()
                }
            }
        }
        .sheet(isPresented: $showingCameraSheet) {
            NavigationStack {
                AnnotationCameraCaptureSheet(
                    mode: cameraMode,
                    cameraPreview: cameraPreview,
                    coordinateSpaceID: coordinateSpaceID,
                    probePlacementTarget: probePlacementTarget,
                    probeCameraHeading: probeCameraHeading,
                    capturePlacement: captureTargetedPlacement,
                    captureOrientation: captureSpeakerOrientation,
                    roomPlanObjects: roomPlanObjects
                ) { result in
                    switch result {
                    case .placement(let authority):
                        placementAuthority = authority
                        positionEdited = false
                        evidenceSelection
                            .replacePlacementAuthority(authority)
                    case .orientation(let authority):
                        orientationAuthority = authority
                        evidenceSelection
                            .replaceOrientationAuthority(authority)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCatalogPicker) {
            NavigationStack {
                EquipmentCatalogPickerSheet(
                    entries: equipmentCatalogEntries,
                    compatibleIdentityKinds: nil,
                    currentSelectionKey:
                        selectedEquipmentKey.isEmpty
                            ? nil : selectedEquipmentKey,
                    recents: equipmentRecents
                ) { entry in
                    selectedEquipmentKey = entry.selectionKey
                    equipmentID = entry.definitionID
                    equipmentVersion = entry.version
                    equipmentHash = entry.semanticSHA256.description
                    equipmentAuthorityVersion =
                        HTDTEquipmentCatalogSnapshot
                            .expectedAuthorityVersion
                }
            }
        }
        .sheet(item: $scanResult) { result in
            NavigationStack {
                EquipmentLabelScanSheet(result: result) { candidate in
                    applyScanCandidate(candidate, from: result)
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var positionSection: some View {
        Section(String(localized: "Position")) {
            if let captured = placementAuthority {
                LabeledContent(
                    String(localized: "Placed by"),
                    value: AnnotationPresentation
                        .placementMethodName(
                            captured.placement.method
                        )
                )
                let p = captured.worldFromAnnotation
                    .translationWorld
                Text(
                    String(
                        format: "(%.2f, %.2f, %.2f) m",
                        Double(p.x), Double(p.y), Double(p.z)
                    )
                )
                .font(.caption.monospacedDigit())
                if cameraPreview != nil && !spatialCaptureSealed {
                Button(
                    String(localized: "Capture again with camera")
                ) {
                    cameraMode = .position
                    showingCameraSheet = true
                }
                }
                Button(
                    String(localized: "Use manual position instead")
                ) {
                    placementAuthority = nil
                    evidenceSelection.replacePlacementAuthority(nil)
                    positionEdited = true
                }
            } else {
                if cameraPreview != nil && !spatialCaptureSealed {
                    Button {
                        cameraMode = .position
                        showingCameraSheet = true
                    } label: {
                        Label(
                            String(localized: "Place with camera"),
                            systemImage: "camera.viewfinder"
                        )
                    }
                }
                Text(
                    "Enter the position manually below, or place it with the camera."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var referencePointSection: some View {
        Section(String(localized: "Reference point")) {
            let constructions = availableConstructions
            if constructions.count > 1 {
                Picker(
                    String(localized: "Construction"),
                    selection: $referencePointConstruction
                ) {
                    DescribedPickerOption(
                        title: String(localized:
                            "Confirmed surface hit"),
                        detail: AnnotationPresentation
                            .constructionDescription(
                                .surfaceHitConfirmed
                            )
                    )
                    .tag(ReferencePointConstruction.surfaceHitConfirmed)
                    DescribedPickerOption(
                        title: String(localized: "Offset from surface"),
                        detail: AnnotationPresentation
                            .constructionDescription(
                                .offsetFromSurface
                            )
                    )
                    .tag(ReferencePointConstruction.offsetFromSurface)
                }
            } else {
                LabeledContent(
                    String(localized: "Construction"),
                    value: String(localized: "Direct placement")
                )
            }
            if referencePointConstruction == .offsetFromSurface,
               constructions.contains(.offsetFromSurface)
            {
                HStack {
                    TextField(
                        String(localized: "Offset X (m)"),
                        text: $offsetXText
                    )
                    .decimalKeyboard()
                    TextField(
                        String(localized: "Offset Y (m)"),
                        text: $offsetYText
                    )
                    .decimalKeyboard()
                    TextField(
                        String(localized: "Offset Z (m)"),
                        text: $offsetZText
                    )
                    .decimalKeyboard()
                }
                Text(
                    "The offset is applied in capture-world axes to the captured hit — e.g. ear height above a seat hit — so the semantic point does not silently coincide with an arbitrary surface."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: availableConstructions) { _, options in
            if !options.contains(referencePointConstruction) {
                referencePointConstruction =
                    options.first ?? .directPlacement
            }
        }
    }

    @ViewBuilder
    private var orientationSection: some View {
        Section(
            isSpeakerLike
                ? String(localized: "Speaker")
                : String(localized: "Orientation")
        ) {
            if isSpeakerLike {
                if let layoutProfile {
                    // Profile-bound logical role picker (#315): the
                    // choice writes both the physical channel_role
                    // token and the exact role_binding triple.
                    let roles = layoutProfile.roles.filter {
                        $0.isSubwoofer == (type == .subwoofer)
                    }
                    Picker(
                        type == .subwoofer
                            ? String(localized: "Subwoofer role")
                            : String(localized: "Logical role"),
                        selection: $selectedRoleBindingID
                    ) {
                        DescribedPickerOption(
                            title: String(localized: "Not assigned"),
                            detail: String(localized:
                                "This item is not bound to a profile role.")
                        )
                        .tag("")
                        ForEach(roles, id: \.roleID) { role in
                            DescribedPickerOption(
                                title: role.displayName
                                    + " (" + role.roleID + ")"
                                    + (role.allowsMultipleBindings
                                        ? " *" : ""),
                                detail: MissionPresentation
                                    .channelRoleName(
                                        role.channelRole
                                    )
                            )
                            .tag(role.roleID)
                        }
                    }
                    .onChange(of: selectedRoleBindingID) {
                        _, roleID in
                        if let definition = layoutProfile
                            .roleDefinition(roleID: roleID)
                        {
                            channelRole = definition.channelRole
                        } else if roleID.isEmpty {
                            channelRole = nil
                        }
                    }
                    if !selectedRoleBindingID.isEmpty {
                        Text(
                            String(localized: "Bound to profile: ")
                                + layoutProfile.profileID
                                + " @ " + layoutProfile.profileVersion
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Picker(
                        type == .subwoofer
                            ? String(localized: "Subwoofer role")
                            : String(localized: "Channel role"),
                        selection: $channelRole
                    ) {
                        DescribedPickerOption(
                            title: String(localized: "Not set"),
                            detail: String(localized:
                                "No channel role — the item is not tied to the audio plan.")
                        )
                        .tag(ChannelRole?.none)
                        ForEach(
                            type == .subwoofer
                                ? ChannelRole.subwooferRoles
                                : ChannelRole.standardRoles,
                            id: \.self
                        ) { role in
                            channelRoleTag(for: role)
                        }
                    }
                }
            }

            // Heading capture is available for every type with
            // body/plane semantics; only speakers *require* it.
            if let captured = orientationAuthority {
                let front =
                    captured.orientation
                        .frontAxisLocal
                LabeledContent(
                    String(localized: "Facing"),
                    value: String(
                        format: "%.0f°",
                        Double(
                            atan2(front.x, -front.z)
                                * 180 / .pi
                        )
                    )
                )
                // #228: the captured aim is full-3D — surface tilt
                // when the front axis is not gravity-horizontal.
                let capturedPitch =
                    asin(
                        max(-1, min(1, Double(front.y)))
                    ) * 180 / .pi
                if abs(capturedPitch) > 0.5 {
                    LabeledContent(
                        String(localized: "Tilt"),
                        value: String(
                            format: "%+.0f°",
                            capturedPitch
                        )
                    )
                }
                if cameraPreview != nil && !spatialCaptureSealed {
                Button(
                    String(localized: "Capture heading again")
                ) {
                    cameraMode = .heading
                    showingCameraSheet = true
                }
                }
                Button(
                    String(localized: "Use manual yaw instead")
                ) {
                    orientationAuthority = nil
                    evidenceSelection
                        .replaceOrientationAuthority(nil)
                }
            } else {
                if cameraPreview != nil && !spatialCaptureSealed {
                    Button {
                        cameraMode = .heading
                        showingCameraSheet = true
                    } label: {
                        Label(
                            String(localized:
                                "Capture facing direction"),
                            systemImage: "location.north"
                        )
                    }
                }
                Text(
                    isSpeakerLike
                        ? String(localized: "Aim the phone the way the speaker faces — tilt counts for Atmos and angled speakers — or enter yaw and elevation in Advanced. Leave both unset when no facing authority exists.")
                        : String(localized: "Aim the phone in the direction this item faces, or enter a yaw angle in Advanced. Leave it unset when no facing authority exists.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var equipmentSection: some View {
        Section(String(localized: "Equipment")) {
            Toggle(
                String(localized: "Attach equipment reference"),
                isOn: $includeEquipmentReference
            )

            if includeEquipmentReference {
                if !equipmentCatalogEntries.isEmpty {
                    Button {
                        showingCatalogPicker = true
                    } label: {
                        Label(
                            selectedEquipmentKey.isEmpty
                                ? String(localized:
                                    "Choose from catalog")
                                : String(localized:
                                    "Change catalog selection"),
                            systemImage: "magnifyingglass"
                        )
                    }

                    if !selectedEquipmentKey.isEmpty,
                       let entry = equipmentCatalogEntries
                           .first(where: {
                               $0.selectionKey
                                   == selectedEquipmentKey
                           })
                    {
                        LabeledContent(
                            String(localized: "Selected"),
                            value: entry.displayName
                        )
                    }
                }

                Text(
                    selectedEquipmentKey.isEmpty
                        ? String(localized:
                            "Enter the exact ID/version/SHA-256 under Advanced, or pick a catalog definition.")
                        : String(localized:
                            "The exact ID/version/SHA-256 tuple is stored as authority.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                // Label-scan assist (#345): runs Vision OCR/barcode on
                // a fresh close-up frame and offers candidates for
                // explicit confirmation — never auto-fills anything.
                if let scanEquipmentLabel {
                    Button {
                        scanLabel(scanEquipmentLabel)
                    } label: {
                        Label(
                            scanningLabel
                                ? String(localized: "Scanning label…")
                                : String(localized:
                                    "Scan equipment label"),
                            systemImage: "barcode.viewfinder"
                        )
                    }
                    .disabled(
                        scanningLabel || cameraPreview == nil
                            || spatialCaptureSealed
                    )
                    if labelScanProvenance != nil {
                        LabeledContent(
                            String(localized: "Label scan"),
                            value: String(localized:
                                "suggested, confirmed by operator")
                        )
                        .font(.caption)
                    }
                }

                // Physical-device identity evidence (#239): optional,
                // explicit, and distinct from placement evidence.
                Section(
                    String(localized: "Physical device identity")
                ) {
                    Button {
                        captureIdentity()
                    } label: {
                        Label(
                            capturingIdentityPhoto
                                ? String(localized: "Capturing…")
                                : String(localized:
                                    "Photograph label / identifying detail"),
                            systemImage: "camera"
                        )
                    }
                    .disabled(
                        capturingIdentityPhoto || cameraPreview == nil
                            || spatialCaptureSealed
                    )
                    if !identityEvidenceRefs.isEmpty {
                        LabeledContent(
                            String(localized: "Identity photos"),
                            value: String(identityEvidenceRefs.count)
                        )
                    }

                    TextField(
                        String(localized:
                            "Serial / asset tag (optional, kept local)"),
                        text: $serialText
                    )
                    .font(.callout)

                    Toggle(
                        String(localized:
                            "This physical unit matches the selected definition"),
                        isOn: $attestedPhysicalMatch
                    )

                    if (!identityEvidenceRefs.isEmpty
                        || !serialText.isEmpty)
                        && !attestedPhysicalMatch
                    {
                        Text(
                            "Not attested — identity evidence is not linked until you confirm the match."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        Section {
            DisclosureGroup(
                String(localized: "Advanced"),
                isExpanded: $showingAdvanced
            ) {
                // Raw schema surfaces kept explicitly available (#220).
                TextField(
                    String(localized: "Raw entity type"),
                    text: .constant(type.rawValue)
                )
                .disabled(true)

                if isSpeakerLike,
                   !(channelRole?.isStandardRole ?? false)
                        || channelRole == nil
                {
                    TextField(
                        String(localized:
                            "Custom channel-role token (L, C, SL, …)"),
                        text: $customRoleText
                    )
                    .onChange(of: customRoleText) { _, text in
                        channelRole = ChannelRole(
                            rawValue: text
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .uppercased()
                        )
                    }
                }

                LabeledContent(
                    String(localized: "Position X"),
                    value: ""
                )
                HStack {
                    TextField("X", text: $xText)
                        .decimalKeyboard()
                    TextField("Y", text: $yText)
                        .decimalKeyboard()
                    TextField("Z", text: $zText)
                        .decimalKeyboard()
                }
                .onChange(of: xText) { _, _ in positionEdited = true }
                .onChange(of: yText) { _, _ in positionEdited = true }
                .onChange(of: zText) { _, _ in positionEdited = true }

                if type.supportsOrientationAuthority,
                   orientationAuthority == nil
                {
                    TextField(
                        String(localized:
                            "Yaw degrees (0 = -Z, 90 = +X)"),
                        text: $yawText
                    )
                    .decimalKeyboard()
                    .onChange(of: yawText) { _, _ in
                        yawEdited = true
                    }
                    if type == .speaker {
                        TextField(
                            String(localized:
                                "Elevation degrees (+ up, - down)"),
                            text: $elevationText
                        )
                        .decimalKeyboard()
                        .onChange(of: elevationText) { _, _ in
                            elevationEdited = true
                        }
                    }
                }

                if includeEquipmentReference {
                    TextField(
                        String(localized: "Equipment ID"),
                        text: $equipmentID
                    )
                    TextField(
                        String(localized: "Equipment version"),
                        text: $equipmentVersion
                    )
                    TextField(
                        String(localized: "Equipment SHA-256"),
                        text: $equipmentHash
                    )
                }

                Text(
                    "Coordinates are meters in the capture world frame; exact schema values for expert corrections."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var pointDirectionSection: some View {
        Section(String(localized: "Point direction")) {
            if let orientationAuthority {
                let front =
                    orientationAuthority.orientation.frontAxisLocal
                let up =
                    orientationAuthority.orientation.upAxisLocal
                LabeledContent(
                    String(localized: "Captured forward"),
                    value: Self.axisText(front)
                )
                LabeledContent(
                    String(localized: "Captured up"),
                    value: Self.axisText(up)
                )
                Button(
                    String(localized: "Remove captured direction")
                ) {
                    self.orientationAuthority = nil
                    evidenceSelection
                        .replaceOrientationAuthority(nil)
                }
            } else {
                Button(
                    String(localized:
                        "Capture current camera direction")
                ) {
                    capturePointDirection()
                }
                .disabled(capturingPointDirection
                    || cameraPreview == nil)
                Text(
                    "Aim the phone along the microphone's acoustic axis, then capture. The full 3D direction — including pitch — is adopted; nothing is flattened to a horizontal heading."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private static func axisText(
        _ axis: SpatialVector3F
    ) -> String {
        "[\(String(format: "%.3f", axis.x)), "
            + "\(String(format: "%.3f", axis.y)), "
            + "\(String(format: "%.3f", axis.z))]"
    }

    // MARK: Actions

    private func capturePointDirection() {
        guard !capturingPointDirection else { return }
        capturingPointDirection = true
        errorText = nil
        Task { @MainActor in
            defer { capturingPointDirection = false }
            do {
                let authority =
                    try await capturePointOrientation()
                orientationAuthority = authority
                evidenceSelection
                    .replaceOrientationAuthority(authority)
            } catch {
                errorText =
                    AnnotationPresentation.errorText(error)
            }
        }
    }

    private func captureIdentity() {
        guard !capturingIdentityPhoto else { return }
        capturingIdentityPhoto = true
        errorText = nil
        Task { @MainActor in
            defer { capturingIdentityPhoto = false }
            do {
                let ref = try await captureIdentityPhoto()
                identityEvidenceRefs.append(ref)
            } catch {
                errorText =
                    AnnotationPresentation.errorText(error)
            }
        }
    }

    private func scanLabel(
        _ scan: @escaping () async throws
            -> EquipmentLabelScanResult
    ) {
        guard !scanningLabel else { return }
        scanningLabel = true
        errorText = nil
        Task { @MainActor in
            defer { scanningLabel = false }
            do {
                scanResult = try await scan()
            } catch {
                errorText =
                    AnnotationPresentation.errorText(error)
            }
        }
    }

    /// Applies a confirmed scan candidate (#345): fills fields only
    /// after the operator explicitly picks a suggestion. Serial stays
    /// editable text, never proof.
    private func applyScanCandidate(
        _ candidate: EquipmentLabelScanCandidate,
        from result: EquipmentLabelScanResult
    ) {
        includeEquipmentReference = true
        if let key = candidate.catalogSelectionKey,
           let entry = equipmentCatalogEntries.first(where: {
               $0.selectionKey == key
           })
        {
            selectedEquipmentKey = entry.selectionKey
            equipmentID = entry.definitionID
            equipmentVersion = entry.version
            equipmentHash = entry.semanticSHA256.description
            equipmentAuthorityVersion =
                HTDTEquipmentCatalogSnapshot
                    .expectedAuthorityVersion
        }
        if let serial = candidate.serialOrAssetTag {
            serialText = serial
        }
        labelScanProvenance = try? EquipmentLabelScanProvenance(
            algorithm: result.algorithm,
            algorithmVersion: result.algorithmVersion,
            evidenceRef: result.evidenceRef,
            matchedRawStrings: candidate.rawStrings
        )
        // The scan image joins the entity's identity evidence.
        if !identityEvidenceRefs.contains(result.evidenceRef) {
            identityEvidenceRefs.append(result.evidenceRef)
        }
    }

    private func save() {
        do {
            // Manual XYZ only overrides the authority when the
            // operator actually edited it (add mode always seeds a
            // numeric position); an untouched field preserves the
            // original placement verbatim — including raycast/mesh
            // provenance a formatted text round-trip would otherwise
            // silently downgrade (#245).
            if placementAuthority == nil {
                guard let x = Double(xText),
                      let y = Double(yText),
                      let z = Double(zText)
                else {
                    throw ManualAuthorityBuilderError.invalidPosition
                }
                if !isEditing || positionEdited {
                    seed.manualPositionOverride = Float3(
                        Float(x), Float(y), Float(z)
                    )
                }
            }
            seed.replacementPlacement = placementAuthority
            seed.replacementOrientation = orientationAuthority

            let equipment: HTDTEquipmentReference?
            if includeEquipmentReference, equipmentCompatible {
                let digest = try EvidenceSHA256(
                    equipmentHash
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .lowercased()
                )
                equipment = try HTDTEquipmentReference(
                    equipmentID: equipmentID,
                    equipmentVersion: equipmentVersion,
                    equipmentHash: digest,
                    authorityVersion: equipmentAuthorityVersion
                        ?? HTDTEquipmentCatalogSnapshot
                            .expectedAuthorityVersion
                )
            } else {
                equipment = nil
            }

            let role: ChannelRole?
            if isSpeakerLike {
                if let channelRole {
                    role = channelRole
                } else {
                    let text = customRoleText
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .uppercased()
                    role = ChannelRole(rawValue: text)
                }
                // #315: an unbound speaker is a valid state — Review
                // surfaces it and missions report the missing role.
                if type == .subwoofer, role == nil {
                    throw ManualAuthorityBuilderError
                        .invalidSubwooferChannelRole
                }
            } else {
                role = nil
            }

            var yawDegrees: Float?
            var speakerElevationDegrees: Float?
            var orientationYawDegrees: Float?
            // Explicit aim removal on edit (#228): clearing the yaw
            // field drops the original aim; leaving it untouched
            // preserves the recorded axes bit-for-bit.
            let speakerAimRemoved =
                type == .speaker && orientationAuthority == nil
                && yawEdited
                && yawText.trimmingCharacters(in: .whitespaces)
                    .isEmpty
            if type.supportsOrientationAuthority,
               orientationAuthority == nil,
               !isEditing || yawEdited || elevationEdited
            {
                // Editing: an untouched yaw field keeps the original
                // orientation axes bit-for-bit; only an edited value
                // rebuilds them (#245). Speaker aim is optional
                // (#228): an unset azimuth leaves the record
                // aim-unknown; other types may leave it unset too.
                let entered =
                    yawText.trimmingCharacters(in: .whitespaces)
                if type == .speaker {
                    if !entered.isEmpty {
                        guard let parsed = Double(entered),
                              parsed.isFinite
                        else {
                            throw ManualAuthorityBuilderError
                                .invalidSpeakerYaw
                        }
                        yawDegrees = Float(parsed)
                    }
                    let elevationEntered =
                        elevationText.trimmingCharacters(
                            in: .whitespaces
                        )
                    if !elevationEntered.isEmpty {
                        // Elevation only refines an azimuth — pitch
                        // without a heading is meaningless.
                        guard yawDegrees != nil,
                              let parsed = Double(elevationEntered),
                              parsed.isFinite
                        else {
                            throw ManualAuthorityBuilderError
                                .invalidSpeakerElevation
                        }
                        speakerElevationDegrees = Float(parsed)
                    }
                } else if !entered.isEmpty {
                    guard let parsed = Double(entered),
                          parsed.isFinite
                    else {
                        throw ManualAuthorityBuilderError
                            .invalidOrientationYaw
                    }
                    orientationYawDegrees = Float(parsed)
                }
            }

            let envelope: EntityPhysicalEnvelope?
            if type != .listeningPosition
                && type != .referencePoint,
               ![envelopeWidthText, envelopeHeightText,
                 envelopeDepthText]
                .allSatisfy({
                    $0.trimmingCharacters(in: .whitespaces)
                        .isEmpty
                })
            {
                let parseDim: (String) throws -> Double? = { text in
                    let trimmed =
                        text.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { return nil }
                    guard let value = Double(trimmed) else {
                        throw AnnotationModelError.invalidEnvelope
                    }
                    return value
                }
                envelope = try EntityPhysicalEnvelope(
                    widthMeters: try parseDim(envelopeWidthText),
                    heightMeters: try parseDim(envelopeHeightText),
                    depthMeters: try parseDim(envelopeDepthText),
                    provenance: .userMeasured
                )
            } else {
                envelope = nil
            }

            let referencePointOffset: SpatialVector3F?
            if placementAuthority != nil,
               referencePointConstruction == .offsetFromSurface
            {
                guard let ox = Double(offsetXText),
                      let oy = Double(offsetYText),
                      let oz = Double(offsetZText)
                else {
                    throw AnnotationModelError
                        .invalidReferencePointAuthority
                }
                referencePointOffset = try SpatialVector3F(
                    Float(ox), Float(oy), Float(oz)
                )
            } else {
                referencePointOffset = nil
            }

            // Logical role binding (#315): only when a profile role
            // is selected; the picker writes it on every change.
            let roleBinding: SpeakerRoleBinding?
            if isSpeakerLike, let layoutProfile,
               !selectedRoleBindingID.isEmpty
            {
                roleBinding = try SpeakerRoleBinding(
                    profileID: layoutProfile.profileID,
                    profileVersion: layoutProfile.profileVersion,
                    roleID: selectedRoleBindingID
                )
            } else {
                roleBinding = nil
            }

            let entity = try seed.buildEntity(
                coordinateSpaceID: coordinateSpaceID,
                type: type,
                label: label,
                channelRole: role,
                roleBinding: roleBinding,
                equipmentRef: equipment,
                yawDegrees: yawDegrees,
                speakerElevationDegrees: speakerElevationDegrees,
                speakerAimRemoved: speakerAimRemoved,
                orientationYawDegrees: orientationYawDegrees,
                listeningRole:
                    type == .listeningPosition ? listeningRole : nil,
                referencePointSemantics: semanticsSelection.isEmpty
                    ? nil
                    : ReferencePointSemantics(
                        rawValue: semanticsSelection
                    ),
                referencePointConstruction:
                    placementAuthority != nil
                    ? referencePointConstruction
                    : nil,
                referencePointOffset: referencePointOffset,
                physicalEnvelope: envelope,
                evidenceSelection: evidenceSelection
            )

            // Equipment identity record (#239): only emitted when the
            // operator explicitly attests the physical match.
            let record: EquipmentIdentityRecord?
            if let equipment, attestedPhysicalMatch {
                record = try EquipmentIdentityRecord(
                    entityID: entity.entityID,
                    equipment: equipment,
                    identityEvidenceRefs: identityEvidenceRefs,
                    serialOrAssetTag:
                        serialText.isEmpty ? nil : serialText,
                    labelScan: labelScanProvenance,
                    attestedPhysicalMatch: true
                )
            } else {
                record = nil
            }

            onSave(entity, record)
            dismiss()
        } catch {
            errorText =
                AnnotationPresentation.errorText(error)
        }
    }

    private func channelRoleTag(
        for role: ChannelRole
    ) -> some View {
        let roleName =
            AnnotationPresentation.channelRoleName(role)
            + " (" + role.rawValue + ")"
        return DescribedPickerOption(
            title: roleName,
            detail: AnnotationPresentation
                .channelRoleDescription(role)
        )
        .tag(ChannelRole?.some(role))
    }

    private static func coordText(_ value: Float) -> String {
        String(format: "%.2f", Double(value))
    }
}


