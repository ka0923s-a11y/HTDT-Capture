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
    public let probePlacementTarget:
        () async -> AnnotationPlacementProbe
    public let probeCameraHeading: () async -> Float?
    public let captureTargetedPlacement: (
        PlacementTargetPreference
    ) async throws -> AnnotationPlacementAuthority?
    public let captureSpeakerOrientation:
        () async throws -> AnnotationOrientationAuthority
    /// Captures a plain evidence frame for equipment identity photos
    /// (#239); returns its canonical `path:` ref.
    public let captureIdentityPhoto: () async throws -> String
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

    // Speaker orientation: captured heading or manual yaw.
    @State private var orientationAuthority:
        AnnotationOrientationAuthority?
    @State private var yawText = ""
    @State private var yawEdited = false

    @State private var includeEquipmentReference = false
    @State private var selectedEquipmentKey = ""
    @State private var equipmentID = ""
    @State private var equipmentVersion = ""
    @State private var equipmentHash = ""

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
        captureIdentityPhoto: @escaping
            () async throws -> String = {
                throw ManualAuthorityBuilderError.invalidPosition
            },
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
        self.probePlacementTarget = probePlacementTarget
        self.probeCameraHeading = probeCameraHeading
        self.captureTargetedPlacement = captureTargetedPlacement
        self.captureSpeakerOrientation = captureSpeakerOrientation
        self.captureIdentityPhoto = captureIdentityPhoto
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
        _yawText = State(
            initialValue: seed.yawDegrees.map {
                String(format: "%.0f", Double($0))
            } ?? "0"
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
        _selectedEquipmentKey = State(
            initialValue: equipmentCatalogEntries.first(where: {
                (try? $0.equipmentReference()) == seed.equipmentRef
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
                        Text(
                            AnnotationPresentation
                                .entityTypeName(value)
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
                    if newType != .speaker {
                        orientationAuthority = nil
                        evidenceSelection
                            .replaceOrientationAuthority(nil)
                    }
                }
                TextField(
                    String(localized: "Label"),
                    text: $label
                )
            }

            positionSection

            if isSpeakerLike {
                speakerSection
            }

            equipmentSection

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
                        .foregroundStyle(.red)
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
                Button(
                    String(localized: "Capture again with camera")
                ) {
                    cameraMode = .position
                    showingCameraSheet = true
                }
                Button(
                    String(localized: "Use manual position instead")
                ) {
                    placementAuthority = nil
                    evidenceSelection.replacePlacementAuthority(nil)
                    positionEdited = true
                }
            } else {
                if cameraPreview != nil {
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
    private var speakerSection: some View {
        Section(String(localized: "Speaker")) {
            Picker(
                String(localized: "Channel role"),
                selection: $channelRole
            ) {
                Text(String(localized: "Not set"))
                    .tag(ChannelRole?.none)
                ForEach(
                    ChannelRole.standardRoles,
                    id: \.self
                ) { role in
                    channelRoleTag(for: role)
                }
            }

            // Heading capture is available for speakers and
            // subwoofers; only speakers *require* it.
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
                Button(
                    String(localized: "Capture heading again")
                ) {
                    cameraMode = .heading
                    showingCameraSheet = true
                }
                Button(
                    String(localized: "Use manual yaw instead")
                ) {
                    orientationAuthority = nil
                    evidenceSelection
                        .replaceOrientationAuthority(nil)
                }
            } else {
                if cameraPreview != nil {
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
                    "Aim the phone the way the speaker faces, or enter a yaw angle in Advanced."
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

                if isSpeakerLike, orientationAuthority == nil {
                    TextField(
                        String(localized:
                            "Yaw degrees (0 = -Z, 90 = +X)"),
                        text: $yawText
                    )
                    .decimalKeyboard()
                    .onChange(of: yawText) { _, _ in
                        yawEdited = true
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

    // MARK: Actions

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
            if includeEquipmentReference {
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
                    equipmentHash: digest
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
                if type == .speaker, role == nil {
                    throw ManualAuthorityBuilderError
                        .invalidSpeakerChannelRole
                }
            } else {
                role = nil
            }

            let yawDegrees: Float?
            if isSpeakerLike, orientationAuthority == nil,
               !isEditing || yawEdited
            {
                // Editing: an untouched yaw field keeps the original
                // orientation axes bit-for-bit; only an edited value
                // rebuilds them (#245).
                if type == .speaker {
                    guard let parsed = Double(yawText),
                          parsed.isFinite
                    else {
                        throw ManualAuthorityBuilderError
                            .invalidSpeakerYaw
                    }
                    yawDegrees = Float(parsed)
                } else {
                    yawDegrees = Double(yawText)
                        .map { Float($0) }
                }
            } else {
                yawDegrees = nil
            }

            let entity = try seed.buildEntity(
                coordinateSpaceID: coordinateSpaceID,
                type: type,
                label: label,
                channelRole: role,
                equipmentRef: equipment,
                yawDegrees: yawDegrees,
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
        return Text(roleName)
            .tag(ChannelRole?.some(role))
    }

    private static func coordText(_ value: Float) -> String {
        String(format: "%.2f", Double(value))
    }
}


