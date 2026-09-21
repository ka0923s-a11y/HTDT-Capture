import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore

/// The canonical annotation/measurement authority already committed in
/// the working revision, reloaded so a pre-finalization correction
/// pass starts from the persisted values instead of blank state (#163).
public struct AnnotationWorkspaceSeed: Sendable, Equatable {
    public let annotations: [CaptureAnnotationEntity]
    public let measurements: [CaptureMeasurement]

    public init(
        annotations: [CaptureAnnotationEntity] = [],
        measurements: [CaptureMeasurement] = []
    ) {
        self.annotations = annotations
        self.measurements = measurements
    }
}

public struct CaptureAnnotationWorkspaceView: View {
    public let coordinateSpaceID: CoordinateSpaceID
    public let availableEvidenceRefs: [String]
    public let statusMessage: String?
    public let replacesCommittedAuthority: Bool
    public let captureRaycastPlacement:
        () async throws -> AnnotationPlacementAuthority
    public let captureSpeakerOrientation:
        () async throws -> AnnotationOrientationAuthority
    /// Validates and adopts an imported catalog snapshot through the
    /// host (#211). The host keeps the catalog alive across this view's
    /// lifecycle (and relaunch, via an app-support cache); the default
    /// only decodes through the validating initializer.
    public let onImportEquipmentCatalog:
        (Data) throws -> HTDTEquipmentCatalogSnapshot
    public let onCommit: (
        [CaptureAnnotationEntity],
        [CaptureMeasurement]
    ) -> Void
    public let onCancel: () -> Void

    @State private var annotations: [CaptureAnnotationEntity]
    @State private var measurements: [CaptureMeasurement]
    @State private var addingAnnotation = false
    @State private var addingMeasurement = false
    /// The catalog snapshot currently adopted by the host, seeded when
    /// this workspace opens (#211). Selecting "Replace equipment
    /// catalog" always runs through `onImportEquipmentCatalog`, so an
    /// unsupported file never silently substitutes the kept snapshot.
    @State private var equipmentCatalog:
        HTDTEquipmentCatalogSnapshot?
    @State private var importingEquipmentCatalog = false
    @State private var equipmentCatalogError: String?

    public init(
        coordinateSpaceID: CoordinateSpaceID,
        availableEvidenceRefs: [String] = [],
        statusMessage: String? = nil,
        seed: AnnotationWorkspaceSeed? = nil,
        replacesCommittedAuthority: Bool = false,
        equipmentCatalog: HTDTEquipmentCatalogSnapshot? = nil,
        captureRaycastPlacement: @escaping
            () async throws -> AnnotationPlacementAuthority = {
                throw ManualAuthorityBuilderError.invalidPosition
            },
        captureSpeakerOrientation: @escaping
            () async throws -> AnnotationOrientationAuthority = {
                throw ManualAuthorityBuilderError.invalidSpeakerYaw
            },
        onImportEquipmentCatalog: @escaping
            (Data) throws -> HTDTEquipmentCatalogSnapshot = { data in
                try JSONDecoder().decode(
                    HTDTEquipmentCatalogSnapshot.self,
                    from: data
                )
            },
        onCommit: @escaping (
            [CaptureAnnotationEntity],
            [CaptureMeasurement]
        ) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.coordinateSpaceID = coordinateSpaceID
        self.availableEvidenceRefs = availableEvidenceRefs.sorted()
        self.statusMessage = statusMessage
        self.replacesCommittedAuthority =
            replacesCommittedAuthority
        self.captureRaycastPlacement = captureRaycastPlacement
        self.captureSpeakerOrientation =
            captureSpeakerOrientation
        self.onImportEquipmentCatalog = onImportEquipmentCatalog
        self.onCommit = onCommit
        self.onCancel = onCancel
        _annotations = State(
            initialValue: seed?.annotations ?? []
        )
        _measurements = State(
            initialValue: seed?.measurements ?? []
        )
        _equipmentCatalog = State(initialValue: equipmentCatalog)
    }

    public var body: some View {
        List {
            if let statusMessage {
                Section("Status") {
                    Text(statusMessage)
                        .font(.callout)
                }
            }

            Section("HTDT equipment catalog") {
                if let equipmentCatalog {
                    LabeledContent(
                        "Definitions",
                        value: String(
                            equipmentCatalog.definitions.count
                        )
                    )
                    Text(
                        "Selections bind exact ID/version/SHA-256 only. The imported catalog is not stored as equipment authority in the capture bundle; it is kept on this device as reference context and can be replaced explicitly."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Optional. Import a catalog snapshot exported from the HTDT backend. Once imported it stays available for later annotation sessions on this device."
                    )
                    .foregroundStyle(.secondary)
                }

                Button(
                    equipmentCatalog == nil
                    ? String(localized: "Import equipment catalog")
                    : String(localized: "Replace equipment catalog")
                ) {
                    importingEquipmentCatalog = true
                }

                if let equipmentCatalogError {
                    Text(equipmentCatalogError)
                        .foregroundStyle(.red)
                }
            }

            Section("Spatial annotations") {
                if annotations.isEmpty {
                    Text("No spatial annotations staged.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(annotations, id: \.entityID) { entity in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entity.label)
                            Text(annotationDetail(entity))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        annotations.remove(atOffsets: offsets)
                    }

                    let findings =
                        AnnotationContractReview.findings(
                            in: annotations
                        )
                    if !findings.isEmpty {
                        ForEach(findings, id: \.self) { finding in
                            Text(
                                finding.severity.rawValue
                                    + ": "
                                    + finding.detail
                            )
                            .font(.caption)
                            .foregroundStyle(
                                finding.severity == .info
                                    ? Color.secondary
                                    : Color.orange
                            )
                        }
                    }
                }

                Button("Add spatial annotation") {
                    addingAnnotation = true
                }
            }

            Section("Measurements") {
                if measurements.isEmpty {
                    Text("No measurements staged.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        measurements,
                        id: \.measurementID
                    ) { measurement in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(measurement.quantityType)
                            Text(measurementDetail(measurement))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        measurements.remove(atOffsets: offsets)
                    }
                }

                Button("Add measurement") {
                    addingMeasurement = true
                }
            }

            Section {
                Button(
                    replacesCommittedAuthority
                    ? String(
                        localized:
                            "Replace saved annotation authority"
                    )
                    : String(
                        localized: "Save annotation authority"
                    )
                ) {
                    onCommit(annotations, measurements)
                }
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
            } footer: {
                if replacesCommittedAuthority {
                    Text(
                        "Save replaces the canonical annotation and measurement collections committed earlier in this revision. Cancelling leaves the previous save unchanged."
                    )
                } else {
                    Text(
                        "Save writes the canonical annotation and measurement collections once. Edit or delete staged records before saving."
                    )
                }
            }
        }
        .sheet(isPresented: $addingAnnotation) {
            NavigationStack {
                ManualAnnotationForm(
                    coordinateSpaceID: coordinateSpaceID,
                    availableEvidenceRefs: availableEvidenceRefs,
                    captureRaycastPlacement:
                        captureRaycastPlacement,
                    captureSpeakerOrientation:
                        captureSpeakerOrientation,
                    equipmentCatalogEntries:
                        equipmentCatalog?.definitions ?? []
                ) { entity in
                    annotations.append(entity)
                }
            }
        }
        .sheet(isPresented: $addingMeasurement) {
            NavigationStack {
                ManualMeasurementForm(
                    availableEvidenceRefs: availableEvidenceRefs
                ) { measurement in
                    measurements.append(measurement)
                }
            }
        }
        .fileImporter(
            isPresented: $importingEquipmentCatalog,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importEquipmentCatalog(result)
        }
    }

    private func importEquipmentCatalog(
        _ result: Result<[URL], Error>
    ) {
        do {
            let urls = try result.get()
            guard let url = urls.first else {
                return
            }
            let accessing =
                url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            // The host validates (schema + authority version), adopts
            // and durably caches the snapshot (#211). A failed import
            // keeps the previously adopted catalog instead of clearing
            // it: the error is shown and nothing is silently replaced.
            equipmentCatalog = try onImportEquipmentCatalog(data)
            equipmentCatalogError = nil
        } catch {
            equipmentCatalogError =
                String(localized: "Catalog import failed: ")
                + String(describing: error)
        }
    }

    private func annotationDetail(
        _ entity: CaptureAnnotationEntity
    ) -> String {
        var parts = [entity.type.rawValue]
        if let role = entity.channelRole {
            parts.append(role.rawValue)
        }
        if let role = entity.listeningRole {
            parts.append(role.rawValue)
        }
        if entity.physicalEnvelope != nil {
            parts.append("envelope")
        }
        return parts.joined(separator: " · ")
    }

    private func measurementDetail(
        _ measurement: CaptureMeasurement
    ) -> String {
        switch measurement.value {
        case let .scalar(value):
            return String(value) + " " + measurement.unit.rawValue
        case let .vector3(x, y, z):
            return "[\(x), \(y), \(z)] "
                + measurement.unit.rawValue
        }
    }
}

private struct ManualAnnotationForm: View {
    let coordinateSpaceID: CoordinateSpaceID
    let availableEvidenceRefs: [String]
    let captureRaycastPlacement:
        () async throws -> AnnotationPlacementAuthority
    let captureSpeakerOrientation:
        () async throws -> AnnotationOrientationAuthority
    let equipmentCatalogEntries: [HTDTEquipmentCatalogEntry]
    let onAdd: (CaptureAnnotationEntity) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var type: AnnotationEntityType = .listeningPosition
    @State private var label = "MLP"
    @State private var xText = "0"
    @State private var yText = "0"
    @State private var zText = "1.1"
    @State private var channelRole = "L"
    @State private var yawText = "0"

    @State private var includeEquipmentReference = false
    @State private var equipmentID = ""
    @State private var equipmentVersion = ""
    @State private var equipmentHash = ""
    @State private var selectedEquipmentKey = ""
    // Issue #207: evidence refs carry ownership — user-selected refs
    // survive authority reverts; authority-owned refs disappear with
    // the authority that introduced them.
    @State private var evidenceSelection =
        AnnotationEvidenceSelection()
    @State private var placementAuthority:
        AnnotationPlacementAuthority?
    @State private var isCapturingRaycast = false
    @State private var orientationAuthority:
        AnnotationOrientationAuthority?
    @State private var isCapturingOrientation = false

    @State private var listeningRole: ListeningPositionRole = .primary
    @State private var semanticsSelection = ""
    @State private var referencePointConstruction:
        ReferencePointConstruction = .surfaceHitConfirmed
    @State private var offsetXText = "0"
    @State private var offsetYText = "0"
    @State private var offsetZText = "0"
    @State private var envelopeWidthText = ""
    @State private var envelopeHeightText = ""
    @State private var envelopeDepthText = ""

    @State private var errorText: String?

    /// The current HTDT catalog's acoustic-source authority only
    /// covers speaker/subwoofer annotations (#237); other types never
    /// see the equipment picker.
    private var equipmentCompatible: Bool {
        HTDTEquipmentCompatibility.compatibleTypes(
            authorityVersion: HTDTEquipmentCatalogSnapshot
                .expectedAuthorityVersion
        )?.contains(type) ?? false
    }

    var body: some View {
        Form {
            Section("Authority") {
                Picker("Type", selection: $type) {
                    ForEach(
                        AnnotationEntityType.allCases,
                        id: \.self
                    ) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .onChange(of: type) { _, newType in
                    channelRole = newType == .subwoofer ? "LFE1" : "L"
                    yawText = newType == .speaker ? "0" : ""
                    semanticsSelection = ""
                    if !equipmentCompatible {
                        includeEquipmentReference = false
                        selectedEquipmentKey = ""
                    }
                }
                TextField("Label", text: $label)
            }

            if type == .listeningPosition {
                Section("Listening position role") {
                    Picker("Role", selection: $listeningRole) {
                        ForEach(
                            ListeningPositionRole.allCases,
                            id: \.self
                        ) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    Text(
                        "The role is machine-readable; the label stays a free human name. Exactly one primary MLP is expected per layout."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Position in capture world (m)") {
                TextField("X", text: $xText)
                    .disabled(placementAuthority != nil)
                TextField("Y", text: $yText)
                    .disabled(placementAuthority != nil)
                TextField("Z", text: $zText)
                    .disabled(placementAuthority != nil)

                if placementAuthority == nil {
                    Button("Use live center raycast") {
                        captureRaycast()
                    }
                    .disabled(isCapturingRaycast)
                } else {
                    LabeledContent(
                        "Placement",
                        value: "evidence-linked raycast"
                    )
                    Button("Use manual position instead") {
                        placementAuthority = nil
                        evidenceSelection
                            .replacePlacementAuthority(nil)
                    }
                }
            }

            if placementAuthority != nil {
                Section("Reference point") {
                    Picker(
                        "Construction",
                        selection: $referencePointConstruction
                    ) {
                        Text("Confirmed surface hit")
                            .tag(
                                ReferencePointConstruction
                                    .surfaceHitConfirmed
                            )
                        Text("Offset from surface")
                            .tag(
                                ReferencePointConstruction
                                    .offsetFromSurface
                            )
                    }
                    if referencePointConstruction
                        == .offsetFromSurface
                    {
                        TextField("Offset X (m)", text: $offsetXText)
                        TextField("Offset Y (m)", text: $offsetYText)
                        TextField("Offset Z (m)", text: $offsetZText)
                        Text(
                            "The offset is applied in capture-world axes to the raycast hit — e.g. ear height above a seat hit — so the semantic point does not silently coincide with an arbitrary surface."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if let semantics = type.allowedReferenceSemantics,
               semantics.count > 1
            {
                Section("Reference point semantics") {
                    Picker("Semantics", selection: $semanticsSelection) {
                        Text("Type default").tag("")
                        ForEach(
                            semantics.sorted {
                                $0.rawValue < $1.rawValue
                            },
                            id: \.self
                        ) { token in
                            Text(token.rawValue).tag(token.rawValue)
                        }
                    }
                }
            }

            if type != .listeningPosition && type != .referencePoint {
                Section("Physical envelope (m, optional)") {
                    TextField("Width", text: $envelopeWidthText)
                    TextField("Height", text: $envelopeHeightText)
                    TextField("Depth", text: $envelopeDepthText)
                    Text(
                        "Dimensions are stored with user_measured provenance. Leave blank when unknown — nothing is inferred."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if type.supportsOrientationAuthority {
                Section("Orientation") {
                    if type == .speaker || type == .subwoofer {
                        TextField(
                            type == .subwoofer
                            ? "Subwoofer role (LFE1, LFE2, ...)"
                            : "Channel role (L, C, R, ...)",
                            text: $channelRole
                        )
                    }

                    if let orientationAuthority {
                        let front =
                            orientationAuthority
                                .orientation.frontAxisLocal
                        LabeledContent(
                            "Captured front",
                            value:
                                "["
                                + String(format: "%.3f", front.x)
                                + ", 0, "
                                + String(format: "%.3f", front.z)
                                + "]"
                        )
                        Button("Use manual yaw instead") {
                            self.orientationAuthority = nil
                            evidenceSelection
                                .replaceOrientationAuthority(nil)
                        }
                    } else {
                        TextField(
                            "Yaw degrees (0 = -Z, 90 = +X)",
                            text: $yawText
                        )
                        Button(
                            "Capture current camera heading"
                        ) {
                            captureOrientation()
                        }
                        .disabled(isCapturingOrientation)
                        Text(
                            "Point the phone in the entity's forward direction, then capture. Only the horizontal heading is adopted; leave yaw blank when no facing authority exists."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if !availableEvidenceRefs.isEmpty {
                EvidenceReferenceSelector(
                    availableEvidenceRefs:
                        availableEvidenceRefs,
                    selectedEvidenceRefs:
                        $evidenceSelection.userSelected
                )
            }

            if equipmentCompatible {
                Section("Pinned HTDT equipment authority") {
                Toggle(
                    "Attach equipment reference",
                    isOn: $includeEquipmentReference
                )

                if includeEquipmentReference {
                    if !equipmentCatalogEntries.isEmpty {
                        Picker(
                            "Catalog definition",
                            selection: $selectedEquipmentKey
                        ) {
                            Text("Manual exact reference")
                                .tag("")
                            ForEach(
                                equipmentCatalogEntries,
                                id: \.selectionKey
                            ) { entry in
                                Text(
                                    entry.displayName
                                    + " · "
                                    + entry.version
                                )
                                .tag(entry.selectionKey)
                            }
                        }
                        .onChange(
                            of: selectedEquipmentKey
                        ) { _, newValue in
                            applyEquipmentSelection(
                                newValue
                            )
                        }
                    }

                    TextField(
                        "Equipment ID",
                        text: $equipmentID
                    )
                    .disabled(!selectedEquipmentKey.isEmpty)
                    TextField(
                        "Equipment version",
                        text: $equipmentVersion
                    )
                    .disabled(!selectedEquipmentKey.isEmpty)
                    TextField(
                        "Equipment SHA-256",
                        text: $equipmentHash
                    )
                    .disabled(!selectedEquipmentKey.isEmpty)

                    Text(
                        selectedEquipmentKey.isEmpty
                        ? String(localized: "All three values are required. The capture app does not guess an equipment revision.")
                        : String(localized: "Selected from an HTDT catalog snapshot; the exact ID/version/SHA-256 tuple is stored.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add annotation")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    add()
                }
            }
        }
    }

    private func applyEquipmentSelection(
        _ selectionKey: String
    ) {
        guard !selectionKey.isEmpty,
              let entry =
                equipmentCatalogEntries.first(where: {
                    $0.selectionKey == selectionKey
                })
        else {
            return
        }

        equipmentID = entry.definitionID
        equipmentVersion = entry.version
        equipmentHash =
            entry.semanticSHA256.description
    }

    private func captureOrientation() {
        guard !isCapturingOrientation else {
            return
        }
        isCapturingOrientation = true
        errorText = nil

        Task { @MainActor in
            defer {
                isCapturingOrientation = false
            }
            do {
                let authority =
                    try await captureSpeakerOrientation()
                orientationAuthority = authority
                evidenceSelection
                    .replaceOrientationAuthority(authority)
            } catch {
                errorText = String(describing: error)
            }
        }
    }

    private func captureRaycast() {
        guard !isCapturingRaycast else {
            return
        }
        isCapturingRaycast = true
        errorText = nil

        Task { @MainActor in
            defer {
                isCapturingRaycast = false
            }
            do {
                let authority =
                    try await captureRaycastPlacement()
                placementAuthority = authority
                xText = String(
                    Double(
                        authority.worldFromAnnotation.values[12]
                    )
                )
                yText = String(
                    Double(
                        authority.worldFromAnnotation.values[13]
                    )
                )
                zText = String(
                    Double(
                        authority.worldFromAnnotation.values[14]
                    )
                )
                evidenceSelection
                    .replacePlacementAuthority(authority)
            } catch {
                errorText = String(describing: error)
            }
        }
    }

    private func add() {
        do {
            guard let x = Double(xText),
                  let y = Double(yText),
                  let z = Double(zText)
            else {
                throw ManualAuthorityBuilderError.invalidPosition
            }

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
                    equipmentHash: digest,
                    authorityVersion: HTDTEquipmentCatalogSnapshot
                        .expectedAuthorityVersion
                )
            } else {
                equipment = nil
            }

            let envelope: EntityPhysicalEnvelope?
            if [envelopeWidthText, envelopeHeightText,
                envelopeDepthText]
                .allSatisfy({
                    $0.trimmingCharacters(in: .whitespaces).isEmpty
                })
            {
                envelope = nil
            } else {
                let parseDim: (String) throws -> Double? = { text in
                    let trimmed =
                        text.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        return nil
                    }
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
                    Float(ox),
                    Float(oy),
                    Float(oz)
                )
            } else {
                referencePointOffset = nil
            }

            let enteredYaw =
                yawText.trimmingCharacters(in: .whitespaces)
            let orientationYawDegrees: Double?
            if type == .speaker || enteredYaw.isEmpty {
                orientationYawDegrees = nil
            } else {
                guard let yaw = Double(enteredYaw) else {
                    throw ManualAuthorityBuilderError
                        .invalidOrientationYaw
                }
                orientationYawDegrees = yaw
            }

            let entity = try ManualAuthorityBuilder.annotation(
                type: type,
                label: label,
                xMeters: x,
                yMeters: y,
                zMeters: z,
                coordinateSpaceID: coordinateSpaceID,
                speakerChannelRole:
                    type == .speaker ? channelRole : nil,
                speakerYawDegrees:
                    type == .speaker ? Double(yawText) : nil,
                subwooferChannelRole:
                    type == .subwoofer ? channelRole : nil,
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
                equipmentReference: equipment,
                evidenceRefs: evidenceSelection.effectiveRefs,
                placementAuthority: placementAuthority,
                orientationAuthority: orientationAuthority
            )
            onAdd(entity)
            dismiss()
        } catch {
            errorText = String(describing: error)
        }
    }
}

private struct ManualMeasurementForm: View {
    let availableEvidenceRefs: [String]
    let onAdd: (CaptureMeasurement) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var quantityType = "room_width"
    @State private var valueText = ""
    @State private var unit: MeasurementUnit = .meter
    @State private var method:
        MeasurementAcquisitionMethod = .laserDistanceMeter
    @State private var uncertaintyText = ""
    @State private var sourceValueText = ""
    @State private var instrumentClass = ""
    @State private var instrumentModel = ""
    @State private var selectedEvidenceRefs = Set<String>()
    @State private var errorText: String?

    private let units: [MeasurementUnit] = [
        .meter,
        .radian,
        .dimensionless,
    ]
    // Derived acquisition methods are intentionally absent: every value
    // this form submits is persisted as `user_attested` /
    // `user_attested_measurement` by ManualAuthorityBuilder, so a manual
    // entry must never claim LiDAR/RoomPlan-derived provenance. Real
    // derived values arrive through their dedicated evidence adapters.
    private let methods: [MeasurementAcquisitionMethod] = [
        .tapeMeasure,
        .laserDistanceMeter,
        .manufacturerSpecification,
        .other,
    ]

    var body: some View {
        Form {
            Section("Measurement") {
                TextField(
                    "Quantity type",
                    text: $quantityType
                )
                TextField("Value", text: $valueText)

                Picker("Unit", selection: $unit) {
                    ForEach(units, id: \.rawValue) {
                        Text($0.rawValue).tag($0)
                    }
                }
                Picker("Acquisition", selection: $method) {
                    ForEach(methods, id: \.rawValue) {
                        Text($0.rawValue).tag($0)
                    }
                }
            }

            if !availableEvidenceRefs.isEmpty {
                EvidenceReferenceSelector(
                    availableEvidenceRefs:
                        availableEvidenceRefs,
                    selectedEvidenceRefs:
                        $selectedEvidenceRefs
                )
            }

            Section("Evidence details") {
                TextField(
                    "Stated uncertainty (optional)",
                    text: $uncertaintyText
                )
                TextField(
                    "Original value text (optional)",
                    text: $sourceValueText
                )
                TextField(
                    "Instrument class (optional)",
                    text: $instrumentClass
                )
                TextField(
                    "Make/model (optional)",
                    text: $instrumentModel
                )
            }

            Section {
                Text(
                    "Manual entries are persisted as user-attested measurements; derived LiDAR/RoomPlan values should use their dedicated evidence path instead."
                )
                .font(.caption)
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add measurement")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    add()
                }
            }
        }
    }

    private func add() {
        do {
            guard let value = Double(valueText) else {
                throw MeasurementModelError.invalidScalar
            }

            let uncertainty: Double?
            if uncertaintyText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            {
                uncertainty = nil
            } else {
                guard let parsed = Double(uncertaintyText) else {
                    throw MeasurementModelError.negativeUncertainty
                }
                uncertainty = parsed
            }

            let instrument: MeasurementInstrument?
            if instrumentClass.isEmpty && instrumentModel.isEmpty {
                instrument = nil
            } else {
                instrument = MeasurementInstrument(
                    instrumentClass:
                        instrumentClass.isEmpty
                        ? nil : instrumentClass,
                    makeModel:
                        instrumentModel.isEmpty
                        ? nil : instrumentModel
                )
            }

            let measurement =
                try ManualAuthorityBuilder.scalarMeasurement(
                    quantityType: quantityType,
                    value: value,
                    unit: unit,
                    acquisitionMethod: method,
                    instrument: instrument,
                    statedUncertainty: uncertainty,
                    sourceValueText:
                        sourceValueText.isEmpty
                        ? nil : sourceValueText,
                    evidenceRefs:
                        selectedEvidenceRefs.sorted()
                )
            onAdd(measurement)
            dismiss()
        } catch {
            errorText = String(describing: error)
        }
    }
}


private struct EvidenceReferenceSelector: View {
    let availableEvidenceRefs: [String]
    @Binding var selectedEvidenceRefs: Set<String>

    var body: some View {
        Section("Linked evidence frames") {
            ForEach(availableEvidenceRefs, id: \.self) { reference in
                Toggle(
                    isOn: Binding(
                        get: {
                            selectedEvidenceRefs.contains(reference)
                        },
                        set: { selected in
                            if selected {
                                selectedEvidenceRefs.insert(reference)
                            } else {
                                selectedEvidenceRefs.remove(reference)
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(frameLabel(reference))
                        Text(reference)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(
                "Links reference exact canonical frame descriptors already persisted in this working revision."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func frameLabel(_ reference: String) -> String {
        let path = reference.hasPrefix("path:")
            ? String(reference.dropFirst(5))
            : reference
        return URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
    }
}
