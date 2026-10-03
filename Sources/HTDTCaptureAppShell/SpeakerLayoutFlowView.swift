import Foundation
import SwiftUI
import HTDTCaptureCore

/// Guided batch speaker/subwoofer layout capture (legacy bolph71656-ai/HTDT-Capture#278). Steps through
/// an explicit `SpeakerLayoutPlan` one role at a time — camera-first
/// placement and heading for each physical loudspeaker — and reports
/// every role's state as completed / missing / skipped / not
/// installed. Equipment reuse between roles is an explicit per-role
/// confirmation; spatial authority (placement + heading) is always
/// freshly captured, never copied.
public struct SpeakerLayoutFlowView: View {
    /// The plan being executed — preset or task-supplied list.
    public let plan: SpeakerLayoutPlan
    /// Entities already staged in the workspace when the flow opened:
    /// their roles count as completed.
    public let existingAnnotations: [CaptureAnnotationEntity]
    public let coordinateSpaceID: CoordinateSpaceID
    public let evidenceFrames: [EvidenceFramePresentation]
    public let equipmentCatalogEntries: [HTDTEquipmentCatalogEntry]
    public let equipmentRecents: EquipmentRecents
    public let roomPlanObjects: [RoomPlanBindableObject]
    public let cameraPreview: AnyView?
    public let probePlacementTarget:
        () async -> AnnotationPlacementProbe
    public let probeCameraHeading: () async -> Float?
    public let captureTargetedPlacement: (
        PlacementTargetPreference
    ) async throws -> AnnotationPlacementAuthority?
    public let captureSpeakerOrientation:
        () async throws -> AnnotationOrientationAuthority
    public let captureIdentityPhoto: () async throws -> String
    /// Each completed entity is appended to the workspace; the last
    /// argument is the optional equipment identity record (legacy bolph71656-ai/HTDT-Capture#239).
    public let onEntity: (
        CaptureAnnotationEntity,
        EquipmentIdentityRecord?
    ) -> Void
    /// Optional catalog update — when the layout ends the workspace
    /// persists the plan inside the workspace draft (legacy bolph71656-ai/HTDT-Capture#266) so a
    /// reopened session resumes mid-flow.
    public let onPlan: (SpeakerLayoutPlan?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var progress: SpeakerLayoutProgress
    @State private var activeRoleID: String?
    @State private var label = ""
    @State private var placementAuthority:
        AnnotationPlacementAuthority?
    @State private var orientationAuthority:
        AnnotationOrientationAuthority?
    @State private var lastEquipmentRef: HTDTEquipmentReference?
    @State private var reuseEquipment = false
    @State private var selectedEquipmentKey = ""
    @State private var identityEvidenceRefs: [String] = []
    @State private var serialText = ""
    @State private var attestedPhysicalMatch = false
    @State private var capturingIdentityPhoto = false
    @State private var showingCameraSheet = false
    @State private var cameraMode: AnnotationCameraCaptureMode =
        .position
    @State private var showingCatalogPicker = false
    @State private var errorText: String?

    public init(
        plan: SpeakerLayoutPlan,
        existingAnnotations: [CaptureAnnotationEntity] = [],
        coordinateSpaceID: CoordinateSpaceID,
        evidenceFrames: [EvidenceFramePresentation] = [],
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
        ) async throws -> AnnotationPlacementAuthority? = { _ in
            nil
        },
        captureSpeakerOrientation: @escaping
            () async throws -> AnnotationOrientationAuthority = {
                throw ManualAuthorityBuilderError.invalidSpeakerYaw
            },
        captureIdentityPhoto: @escaping
            () async throws -> String = {
                throw ManualAuthorityBuilderError.invalidPosition
            },
        onEntity: @escaping (
            CaptureAnnotationEntity,
            EquipmentIdentityRecord?
        ) -> Void,
        onPlan: @escaping (SpeakerLayoutPlan?) -> Void = { _ in }
    ) {
        self.plan = plan
        self.existingAnnotations = existingAnnotations
        self.coordinateSpaceID = coordinateSpaceID
        self.evidenceFrames = evidenceFrames
        self.equipmentCatalogEntries = equipmentCatalogEntries
        self.equipmentRecents = equipmentRecents
        self.roomPlanObjects = roomPlanObjects
        self.cameraPreview = cameraPreview
        self.probePlacementTarget = probePlacementTarget
        self.probeCameraHeading = probeCameraHeading
        self.captureTargetedPlacement = captureTargetedPlacement
        self.captureSpeakerOrientation = captureSpeakerOrientation
        self.captureIdentityPhoto = captureIdentityPhoto
        self.onEntity = onEntity
        self.onPlan = onPlan
        _progress = State(
            initialValue: SpeakerLayoutProgress(
                plan: plan,
                annotations: existingAnnotations
            )
        )
        _activeRoleID = State(
            initialValue: SpeakerLayoutProgress(
                plan: plan,
                annotations: existingAnnotations
            ).nextPendingRole(in: plan)?.roleID
        )
    }

    private var activeRole: SpeakerLayoutRole? {
        plan.roles.first { $0.roleID == activeRoleID }
    }

    public var body: some View {
        List {
            Section(String(localized: "Layout")) {
                Text(plan.planName)
                    .font(.headline)
                ForEach(plan.roles) { role in
                    roleRow(role)
                }
            }

            if let role = activeRole {
                Section(
                    String(localized: "Now capturing: ")
                        + MissionPresentation
                            .layoutRoleDisplayName(role)
                        + " (" + role.channelRole.rawValue + ")"
                ) {
                    TextField(
                        String(localized: "Label"),
                        text: $label
                    )

                    if let placementAuthority {
                        LabeledContent(
                            String(localized: "Placed by"),
                            value: AnnotationPresentation
                                .placementMethodName(
                                    placementAuthority
                                        .placement.method
                                )
                        )
                    }
                    Button {
                        cameraMode = .position
                        showingCameraSheet = true
                    } label: {
                        Label(
                            placementAuthority == nil
                                ? String(localized:
                                    "Place with camera")
                                : String(localized:
                                    "Recapture position"),
                            systemImage: "camera.viewfinder"
                        )
                    }
                    .disabled(cameraPreview == nil)

                    if role.isSubwoofer {
                        Text(
                            "Heading is optional for subwoofers."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Button {
                        cameraMode = .heading
                        showingCameraSheet = true
                    } label: {
                        Label(
                            orientationAuthority == nil
                                ? String(localized:
                                    "Capture facing direction")
                                : String(localized:
                                    "Recapture heading"),
                            systemImage: "location.north"
                        )
                    }
                    .disabled(cameraPreview == nil)

                    equipmentRow(role: role)

                    if let errorText {
                        Text(errorText)
                            .foregroundStyle(CaptureColorRole.blocked.color)
                    }
                }

                Section {
                    Button(
                        String(localized: "Save & next")
                    ) {
                        saveActiveRole()
                    }
                    .disabled(!canSave)

                    HStack {
                        Button(String(localized: "Skip")) {
                            mark(.skipped, role: role)
                        }
                        Spacer()
                        Button(
                            String(localized: "Not installed")
                        ) {
                            mark(.notInstalled, role: role)
                        }
                    }
                }
            } else {
                Section {
                    Text(
                        "Every role in the plan has been captured, skipped, or marked not installed."
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(
            String(localized: "Capture speaker layout")
        )
        .inlineNavigationBarTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done")) {
                    onPlan(plan)
                    dismiss()
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
                    case .orientation(let authority):
                        orientationAuthority = authority
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
                }
            }
        }
        .onAppear {
            if label.isEmpty, let role = activeRole {
                label = MissionPresentation
                    .layoutRoleDisplayName(role)
            }
        }
    }

    @ViewBuilder
    private func roleRow(_ role: SpeakerLayoutRole) -> some View {
        let state = progress.state(for: role.roleID)
        Button {
            activeRoleID = role.roleID
            label = MissionPresentation
                .layoutRoleDisplayName(role)
            placementAuthority = nil
            orientationAuthority = nil
            reuseEquipment = false
            identityEvidenceRefs = []
            serialText = ""
            attestedPhysicalMatch = false
            errorText = nil
        } label: {
            HStack {
                Image(systemName: iconName(for: state))
                    .foregroundStyle(color(for: state))
                Text(MissionPresentation.layoutRoleDisplayName(role))
                    .foregroundStyle(.primary)
                Spacer()
                Text(stateName(state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func equipmentRow(
        role: SpeakerLayoutRole
    ) -> some View {
        if let lastEquipmentRef {
            Toggle(
                String(localized: "Same equipment as previous: ")
                    + lastEquipmentRef.equipmentID,
                isOn: $reuseEquipment
            )
        }
        Button {
            showingCatalogPicker = true
        } label: {
            Label(
                selectedEquipmentKey.isEmpty
                    ? String(localized: "Choose equipment")
                    : String(localized: "Equipment selected"),
                systemImage: "magnifyingglass"
            )
        }
        .disabled(equipmentCatalogEntries.isEmpty)

        // Optional physical-identity evidence for this role (legacy bolph71656-ai/HTDT-Capture#239).
        if !identityEvidenceRefs.isEmpty {
            Text(
                String(localized: "Identity photos: ")
                    + String(identityEvidenceRefs.count)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
        TextField(
            String(localized:
                "Serial / asset tag (optional)"),
            text: $serialText
        )
        Toggle(
            String(localized:
                "This physical unit matches the selected definition"),
            isOn: $attestedPhysicalMatch
        )
    }

    private var canSave: Bool {
        guard let role = activeRole else { return false }
        if role.isSubwoofer {
            return placementAuthority != nil
        }
        return placementAuthority != nil
            && orientationAuthority != nil
    }

    private func mark(
        _ state: SpeakerLayoutRoleState,
        role: SpeakerLayoutRole
    ) {
        switch state {
        case .skipped:
            progress.markSkipped(roleID: role.roleID)
        case .notInstalled:
            progress.markNotInstalled(roleID: role.roleID)
        case .pending:
            progress.markPending(roleID: role.roleID)
        case .completed:
            break
        }
        advance(after: role)
    }

    private func saveActiveRole() {
        guard let role = activeRole else { return }
        do {
            let equipment: HTDTEquipmentReference?
            if reuseEquipment {
                equipment = lastEquipmentRef
            } else if !selectedEquipmentKey.isEmpty,
                      let entry = equipmentCatalogEntries
                          .first(where: {
                              $0.selectionKey == selectedEquipmentKey
                          })
            {
                equipment = try entry.equipmentReference(
                    authorityVersion:
                        HTDTEquipmentCatalogSnapshot
                            .expectedAuthorityVersion
                )
            } else {
                equipment = nil
            }

            var seed = AnnotationEditSeed(
                freshType: role.isSubwoofer ? .subwoofer : .speaker
            )
            // Spatial authority is always the fresh per-role capture —
            // equipment metadata may be reused with confirmation, but
            // placement/heading provenance is never copied.
            seed.replacementPlacement = placementAuthority
            seed.replacementOrientation = orientationAuthority
            // Identity photos bind only to the EquipmentIdentityRecord
            // (legacy bolph71656-ai/HTDT-Capture#239) — they stay out of the entity's spatial
            // evidence_refs.
            let selection = AnnotationEvidenceSelection()
            // The contract is fail-closed: an evidence-captured
            // placement must declare how the semantic point was
            // constructed (legacy bolph71656-ai/HTDT-Capture#291). Surface-derived hits confirm the
            // cabinet surface; a RoomPlan binding is direct.
            let construction: ReferencePointConstruction? =
                placementAuthority.map { authority in
                    switch authority.placement.method {
                    case .raycast, .meshHitTest:
                        return .surfaceHitConfirmed
                    default:
                        return .directPlacement
                    }
                }
            // Profile-bound plan roles (legacy bolph71656-ai/HTDT-Capture#315): entities record the
            // exact {profile_id, profile_version, role_id} binding
            // alongside the physical channel token.
            let roleBinding = try plan.profileIdentity.map {
                identity in
                try SpeakerRoleBinding(
                    profileID: identity.profileID,
                    profileVersion: identity.profileVersion,
                    roleID: role.roleID
                )
            }
            let entity = try seed.buildEntity(
                coordinateSpaceID: coordinateSpaceID,
                type: role.isSubwoofer ? .subwoofer : .speaker,
                label: label.isEmpty
                    ? MissionPresentation.layoutRoleDisplayName(role)
                    : label,
                channelRole: role.channelRole,
                roleBinding: roleBinding,
                equipmentRef: equipment,
                yawDegrees: nil,
                referencePointConstruction: construction,
                evidenceSelection: selection
            )

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

            onEntity(entity, record)
            progress.markCompleted(
                roleID: role.roleID,
                entityID: entity.entityID
            )
            if let equipment {
                lastEquipmentRef = equipment
            }
            errorText = nil
            advance(after: role)
        } catch {
            errorText =
                AnnotationPresentation.errorText(error)
        }
    }

    private func advance(after role: SpeakerLayoutRole) {
        placementAuthority = nil
        orientationAuthority = nil
        reuseEquipment = false
        selectedEquipmentKey = ""
        identityEvidenceRefs = []
        serialText = ""
        attestedPhysicalMatch = false
        activeRoleID =
            progress.nextPendingRole(in: plan)?.roleID
        if let activeRole {
            label = MissionPresentation
                .layoutRoleDisplayName(activeRole)
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

    private func iconName(
        for state: SpeakerLayoutRoleState
    ) -> String {
        switch state {
        case .completed: return "checkmark.circle.fill"
        case .pending: return "circle"
        case .skipped: return "arrow.right.circle"
        case .notInstalled: return "minus.circle"
        }
    }

    private func color(
        for state: SpeakerLayoutRoleState
    ) -> Color {
        switch state {
        case .completed: return .green
        case .pending: return .secondary
        case .skipped: return .orange
        case .notInstalled: return .secondary
        }
    }

    private func stateName(
        _ state: SpeakerLayoutRoleState
    ) -> String {
        switch state {
        case .completed:
            return String(localized: "Captured")
        case .pending:
            return String(localized: "Pending")
        case .skipped:
            return String(localized: "Skipped")
        case .notInstalled:
            return String(localized: "Not installed")
        }
    }
}
