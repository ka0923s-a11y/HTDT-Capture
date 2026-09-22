import Foundation
import SwiftUI
import HTDTCaptureCore

/// Semantic-only correction editor for a finalized capture (issue
/// #319). The parent bundle's committed records are the starting
/// point; the operator edits metadata only — labels, roles,
/// verification/attestation states, equipment identity fields,
/// opening dispositions — never positions or sensor evidence. "Create
/// revision" builds a child bundle whose spatial evidence is carried
/// over byte-for-byte; the parent stays finalized and untouched.
public struct SemanticCorrectionSheet: View {
    /// Decoded parent context plus the record this correction edits.
    public let context: SemanticChildRevisionContext
    public let commit:
        (SemanticChildRevisionEdits) async -> Bool
    public let cancel: () -> Void

    @State private var entities: [CaptureAnnotationEntity]
    @State private var measurements: [CaptureMeasurement]
    @State private var openings: [RoomOpeningCandidate]
    @State private var equipmentRecords: [EquipmentIdentityRecord]
    @State private var correctionNote: String = ""
    @State private var commitInFlight = false
    @Environment(\.dismiss) private var dismiss

    public init(
        context: SemanticChildRevisionContext,
        commit: @escaping (
            SemanticChildRevisionEdits
        ) async -> Bool = { _ in false },
        cancel: @escaping () -> Void = {}
    ) {
        self.context = context
        self.commit = commit
        self.cancel = cancel
        _entities = State(
            initialValue: context.entities
        )
        _measurements = State(
            initialValue: context.measurements
        )
        _openings = State(
            initialValue: context.openingReview?.openings ?? []
        )
        _equipmentRecords = State(
            initialValue: context.equipmentIdentity?.records ?? []
        )
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "This creates a new revision that corrects annotations, measurements, and equipment metadata. The room is not rescanned; the original capture's sensor evidence is preserved exactly."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Correction note") {
                    TextField(
                        String(localized: "What is being corrected"),
                        text: $correctionNote,
                        axis: .vertical
                    )
                    .accessibilityIdentifier(
                        "semanticCorrection.note"
                    )
                }

                if !entities.isEmpty {
                    Section("Annotations") {
                        ForEach(
                            entities.indices,
                            id: \.self
                        ) { index in
                            entityRow(index)
                        }
                    }
                }

                if !measurements.isEmpty {
                    Section("Measurements") {
                        ForEach(
                            measurements.indices,
                            id: \.self
                        ) { index in
                            measurementRow(index)
                        }
                    }
                }

                if !equipmentRecords.isEmpty {
                    Section("Equipment identity") {
                        ForEach(
                            equipmentRecords.indices,
                            id: \.self
                        ) { index in
                            equipmentRow(index)
                        }
                    }
                }

                if !openings.isEmpty {
                    Section("Openings") {
                        ForEach(
                            openings.indices,
                            id: \.self
                        ) { index in
                            openingRow(index)
                        }
                    }
                }
            }
            .navigationTitle("Correct metadata")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create revision") {
                        commitInFlight = true
                        Task {
                            let edits = SemanticChildRevisionEdits(
                                entities: entities,
                                measurements: measurements,
                                openings: openings.isEmpty
                                    ? nil : openings,
                                equipmentRecords:
                                    equipmentRecords.isEmpty
                                        ? nil : equipmentRecords,
                                correctionNote: correctionNote
                            )
                            let done = await commit(edits)
                            commitInFlight = false
                            if done {
                                dismiss()
                            }
                        }
                    }
                    .disabled(commitInFlight)
                    .accessibilityIdentifier(
                        "semanticCorrection.commit"
                    )
                }
            }
            .interactiveDismissDisabled(commitInFlight)
        }
    }

    /// Rebuilds an entity with edited metadata fields. Spatial
    /// authority (`worldFromAnnotation`, placement, orientation,
    /// uncertainty) is never touched by this sheet — only the
    /// label/role/verification metadata the issue scopes (#319).
    private func applyEntityEdit(
        at index: Int,
        label: String? = nil,
        channelRole: ChannelRole? = nil,
        clearsChannelRole: Bool = false,
        listeningRole: ListeningPositionRole? = nil,
        verificationState: AnnotationVerificationState? = nil
    ) {
        let entity = entities[index]
        guard let rebuilt = try? CaptureAnnotationEntity(
            entityID: entity.entityID,
            type: entity.type,
            coordinateSpaceID: entity.coordinateSpaceID,
            worldFromAnnotation: entity.worldFromAnnotation,
            referencePointSemantics: entity.referencePointSemantics,
            label: label ?? entity.label,
            provenanceClass: entity.provenanceClass,
            verificationState:
                verificationState ?? entity.verificationState,
            placement: entity.placement,
            orientation: entity.orientation,
            channelRole: clearsChannelRole
                ? nil
                : channelRole ?? entity.channelRole,
            acousticCenter: entity.acousticCenter,
            equipmentRef: entity.equipmentRef,
            evidenceRefs: entity.evidenceRefs,
            physicalEnvelope: entity.physicalEnvelope,
            listeningRole: listeningRole ?? entity.listeningRole,
            uncertainty: entity.uncertainty,
            authority: entity.authority,
            lifecycle: entity.lifecycle,
            referencePoint: entity.referencePoint
        ) else {
            return
        }
        entities[index] = rebuilt
    }

    private func applyMeasurementEdit(
        at index: Int,
        value: MeasurementValue? = nil,
        statedUncertainty: Double? = nil,
        clearsUncertainty: Bool = false,
        attestation: UserAttestationState? = nil,
        sourceValueText: String? = nil
    ) {
        let measurement = measurements[index]
        guard let rebuilt = try? CaptureMeasurement(
            measurementID: measurement.measurementID,
            quantityType: measurement.quantityType,
            value: value ?? measurement.value,
            unit: measurement.unit,
            coordinateSpaceID: measurement.coordinateSpaceID,
            endpointRefs: measurement.endpointRefs,
            acquisitionMethod: measurement.acquisitionMethod,
            instrument: measurement.instrument,
            statedUncertainty: clearsUncertainty
                ? nil
                : statedUncertainty
                    ?? measurement.statedUncertainty,
            observedAtUTC: measurement.observedAtUTC,
            userAttestation:
                attestation ?? measurement.userAttestation,
            provenanceClass: measurement.provenanceClass,
            sourceValueText:
                sourceValueText ?? measurement.sourceValueText,
            sourceAuthority: measurement.sourceAuthority,
            derivation: measurement.derivation,
            evidenceRefs: measurement.evidenceRefs
        ) else {
            return
        }
        measurements[index] = rebuilt
    }

    private func applyEquipmentEdit(
        at index: Int,
        serialOrAssetTag: String? = nil,
        attested: Bool? = nil
    ) {
        let record = equipmentRecords[index]
        guard let rebuilt = try? EquipmentIdentityRecord(
            entityID: record.entityID,
            equipment: record.equipment,
            identityEvidenceRefs: record.identityEvidenceRefs,
            serialOrAssetTag:
                serialOrAssetTag ?? record.serialOrAssetTag,
            attestedPhysicalMatch:
                attested ?? record.attestedPhysicalMatch,
            recordedAtUTC: record.recordedAtUTC
        ) else {
            return
        }
        equipmentRecords[index] = rebuilt
    }

    private func applyOpeningEdit(
        at index: Int,
        disposition: RoomOpeningDisposition
    ) {
        openings[index].disposition = disposition
        openings[index].reviewedAtUTC = BundleTimestamp.utcString(
            from: Date()
        )
    }

    @ViewBuilder
    private func entityRow(_ index: Int) -> some View {
        let entity = entities[index]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(
                    MissionPresentation.annotationEntityTypeName(
                        entity.type
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
            }
            TextField(
                String(localized: "Label"),
                text: Binding(
                    get: { entities[index].label },
                    set: { applyEntityEdit(at: index, label: $0) }
                )
            )
            if entity.type == .speaker || entity.type == .subwoofer {
                Picker(
                    String(localized: "Channel role"),
                    selection: Binding(
                        get: {
                            entities[index].channelRole?.rawValue
                                ?? ""
                        },
                        set: {
                            if let role = ChannelRole(rawValue: $0) {
                                applyEntityEdit(
                                    at: index,
                                    channelRole: role
                                )
                            } else if entities[index].type
                                != .speaker
                            {
                                applyEntityEdit(
                                    at: index,
                                    clearsChannelRole: true
                                )
                            }
                        }
                    )
                ) {
                    DescribedPickerOption(
                        title: String(localized: "None"),
                        detail: String(localized:
                            "Leave this item without a channel role.")
                    )
                    .tag("")
                    ForEach(
                        Self.commonChannelRoles,
                        id: \.self
                    ) { role in
                        DescribedPickerOption(
                            title: MissionPresentation
                                .channelRoleName(role),
                            detail: AnnotationPresentation
                                .channelRoleDescription(role)
                        )
                        .tag(role.rawValue)
                    }
                }
            }
            if entity.type == .listeningPosition {
                Picker(
                    String(localized: "Listening role"),
                    selection: Binding(
                        get: {
                            entities[index].listeningRole
                                ?? .secondary
                        },
                        set: {
                            applyEntityEdit(
                                at: index,
                                listeningRole: $0
                            )
                        }
                    )
                ) {
                    ForEach(
                        ListeningPositionRole.allCases,
                        id: \.self
                    ) { role in
                        DescribedPickerOption(
                            title: MissionPresentation
                                .listeningPositionRoleName(role),
                            detail: AnnotationPresentation
                                .listeningRoleDescription(role)
                        )
                        .tag(role)
                    }
                }
            }
            Picker(
                String(localized: "Verification"),
                selection: Binding(
                    get: { entities[index].verificationState },
                    set: {
                        applyEntityEdit(
                            at: index,
                            verificationState: $0
                        )
                    }
                )
            ) {
                DescribedPickerOption(
                    title: String(localized: "Unverified"),
                    detail: AnnotationPresentation
                        .verificationStateDescription(
                            .unverified
                        )
                )
                .tag(AnnotationVerificationState.unverified)
                DescribedPickerOption(
                    title: String(localized: "User attested"),
                    detail: AnnotationPresentation
                        .verificationStateDescription(
                            .userAttested
                        )
                )
                .tag(AnnotationVerificationState.userAttested)
                DescribedPickerOption(
                    title: String(localized: "Evidence linked"),
                    detail: AnnotationPresentation
                        .verificationStateDescription(
                            .evidenceLinked
                        )
                )
                .tag(AnnotationVerificationState.evidenceLinked)
            }
        }
    }

    private static let commonChannelRoles: [ChannelRole] = [
        .left, .center, .right,
        .surroundLeft, .surroundRight,
        .surroundBackLeft, .surroundBackRight,
        .lfe, .lfe1, .lfe2, .lfe3, .lfe4,
        .topFrontLeft, .topFrontRight,
        .topMiddleLeft, .topMiddleRight,
        .topRearLeft, .topRearRight,
    ]

    @ViewBuilder
    private func measurementRow(_ index: Int) -> some View {
        let measurement = measurements[index]
        VStack(alignment: .leading, spacing: 4) {
            Text(
                AnnotationPresentation.measurementTitle(
                    forQuantityType: measurement.quantityType
                )
                    + " · "
                    + MissionPresentation.measurementUnitSymbol(
                        measurement.unit
                    )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if case let .scalar(scalar) = measurement.value {
                TextField(
                    String(localized: "Value"),
                    text: Binding(
                        get: { String(scalar) },
                        set: {
                            if let parsed = Double($0),
                               parsed.isFinite
                            {
                                applyMeasurementEdit(
                                    at: index,
                                    value: .scalar(parsed)
                                )
                            }
                        }
                    )
                )
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            }
            Toggle(
                String(localized: "Operator attested"),
                isOn: Binding(
                    get: {
                        measurements[index].userAttestation
                            == .attested
                    },
                    set: {
                        applyMeasurementEdit(
                            at: index,
                            attestation:
                                $0 ? .attested : .notAttested
                        )
                    }
                )
            )
            TextField(
                String(localized: "Stated uncertainty"),
                text: Binding(
                    get: {
                        measurements[index].statedUncertainty
                            .map { String($0) } ?? ""
                    },
                    set: {
                        if $0.isEmpty {
                            applyMeasurementEdit(
                                at: index,
                                clearsUncertainty: true
                            )
                        } else if let parsed = Double($0),
                                  parsed.isFinite,
                                  parsed >= 0
                        {
                            applyMeasurementEdit(
                                at: index,
                                statedUncertainty: parsed
                            )
                        }
                    }
                )
            )
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
        }
    }

    @ViewBuilder
    private func equipmentRow(_ index: Int) -> some View {
        let record = equipmentRecords[index]
        VStack(alignment: .leading, spacing: 4) {
            Text(record.equipment.equipmentID)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "Serial or asset tag"),
                text: Binding(
                    get: {
                        equipmentRecords[index].serialOrAssetTag
                            ?? ""
                    },
                    set: {
                        applyEquipmentEdit(
                            at: index,
                            serialOrAssetTag:
                                $0.isEmpty ? nil : $0
                        )
                    }
                )
            )
            Toggle(
                String(localized: "Physical match attested"),
                isOn: Binding(
                    get: {
                        equipmentRecords[index]
                            .attestedPhysicalMatch
                    },
                    set: {
                        applyEquipmentEdit(at: index, attested: $0)
                    }
                )
            )
        }
    }

    @ViewBuilder
    private func openingRow(_ index: Int) -> some View {
        let candidate = openings[index]
        HStack {
            Text(candidate.sourceRef)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker(
                String(localized: "Disposition"),
                selection: Binding(
                    get: { openings[index].disposition },
                    set: { applyOpeningEdit(at: index, disposition: $0) }
                )
            ) {
                DescribedPickerOption(
                    title: String(localized: "Unreviewed"),
                    detail: TheaterAuthorityPresentation
                        .openingDispositionDescription(.unreviewed)
                )
                .tag(RoomOpeningDisposition.unreviewed)
                DescribedPickerOption(
                    title: String(localized: "Confirmed"),
                    detail: TheaterAuthorityPresentation
                        .openingDispositionDescription(.confirmed)
                )
                .tag(RoomOpeningDisposition.confirmed)
                DescribedPickerOption(
                    title: String(localized: "Needs more scanning"),
                    detail: TheaterAuthorityPresentation
                        .openingDispositionDescription(
                            .needsMoreScanning
                        )
                )
                .tag(RoomOpeningDisposition.needsMoreScanning)
                DescribedPickerOption(
                    title: String(localized:
                        "Intentionally ignored"),
                    detail: TheaterAuthorityPresentation
                        .openingDispositionDescription(
                            .intentionallyIgnored
                        )
                )
                .tag(RoomOpeningDisposition.intentionallyIgnored)
            }
            .labelsHidden()
        }
    }
}
