import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore

/// Task-oriented measurement form (#220): the operator picks a common
/// task — room width/length/height, screen size, speaker distances —
/// and the form writes the canonical quantity token. A "Custom
/// measurement" template keeps the free-text path available.
/// Editing an existing measurement preserves its `measurementID`
/// (#245).
public struct MeasurementFormView: View {
    private let editingMeasurement: CaptureMeasurement?

    /// Capture coordinate space the endpoint entity refs resolve in
    /// (issue #215).
    public let coordinateSpaceID: CoordinateSpaceID
    /// Staged entities usable as measurement endpoints (issue #215).
    public let endpointCandidates: [CaptureAnnotationEntity]
    public let evidenceFrames: [EvidenceFramePresentation]
    public let otherEvidenceRefs: [String]
    /// Instrument profiles staged for this revision (#331); picking
    /// one binds the measurement to the exact immutable profile
    /// version + digest. The legacy make/model text stays fillable
    /// alongside it.
    public let instrumentProfiles: [MeasurementInstrumentProfile]
    public let onSave: (CaptureMeasurement) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var quantityType: String
    @State private var templateID: String
    @State private var valueText: String
    @State private var unit: MeasurementUnit
    @State private var method: MeasurementAcquisitionMethod
    @State private var uncertaintyText: String
    @State private var sourceValueText: String
    @State private var instrumentClass: String
    @State private var instrumentModel: String
    @State private var instrumentAuthority:
        MeasurementInstrumentReference?
    @State private var selectedEvidenceRefs: Set<String>
    @State private var endpointA = ""
    @State private var endpointB = ""
    @State private var showingAdvanced = false
    @State private var errorText: String?
    @State private var importingInstrumentReading = false
    @State private var instrumentSession =
        InstrumentMeasurementSession()
    @State private var importMakeModel = ""
    @State private var importMethod: MeasurementAcquisitionMethod =
        .externalInstrument

    // Derived acquisition methods are intentionally absent: every
    // value this form submits is persisted as `user_attested` /
    // `user_attested_measurement`; a manual entry must never claim
    // LiDAR/RoomPlan-derived provenance.
    private let methods: [MeasurementAcquisitionMethod] = [
        .tapeMeasure,
        .laserDistanceMeter,
        .manufacturerSpecification,
        .other,
    ]

    /// Physical methods the file/document instrument adapter may
    /// declare (issue #226/#355). Derived methods are rejected by the
    /// descriptor itself — an instrument never produces them.
    private let importMethods: [MeasurementAcquisitionMethod] = [
        .externalInstrument,
        .laserDistanceMeter,
        .tapeMeasure,
        .other,
    ]

    public init(
        editingMeasurement: CaptureMeasurement? = nil,
        coordinateSpaceID: CoordinateSpaceID,
        endpointCandidates: [CaptureAnnotationEntity] = [],
        evidenceFrames: [EvidenceFramePresentation] = [],
        otherEvidenceRefs: [String] = [],
        instrumentProfiles: [MeasurementInstrumentProfile] = [],
        onSave: @escaping (CaptureMeasurement) -> Void
    ) {
        self.editingMeasurement = editingMeasurement
        self.coordinateSpaceID = coordinateSpaceID
        self.endpointCandidates = endpointCandidates
        self.evidenceFrames = evidenceFrames
        self.otherEvidenceRefs = otherEvidenceRefs
        self.instrumentProfiles = instrumentProfiles
        self.onSave = onSave

        let seed = editingMeasurement
        let initialType = seed?.quantityType ?? "room_width"
        _quantityType = State(initialValue: initialType)
        _templateID = State(
            initialValue: AnnotationPresentation.measurementTemplates
                .first { $0.quantityType == initialType }?.id
                ?? "custom"
        )
        let scalarValue: Double? = seed.flatMap {
            if case let .scalar(value) = $0.value {
                return value
            }
            return nil
        }
        _valueText = State(
            initialValue: scalarValue.map { String($0) } ?? ""
        )
        _unit = State(initialValue: seed?.unit ?? .meter)
        _method = State(
            initialValue: seed?.acquisitionMethod
                ?? .laserDistanceMeter
        )
        _uncertaintyText = State(
            initialValue: seed?.statedUncertainty
                .map { String($0) } ?? ""
        )
        _sourceValueText = State(
            initialValue: seed?.sourceValueText ?? ""
        )
        _instrumentClass = State(
            initialValue: seed?.instrument?.instrumentClass ?? ""
        )
        _instrumentModel = State(
            initialValue: seed?.instrument?.makeModel ?? ""
        )
        _instrumentAuthority = State(
            initialValue: seed?.instrumentAuthority
        )
        _selectedEvidenceRefs = State(
            initialValue: Set(seed?.evidenceRefs ?? [])
        )
    }

    public var body: some View {
        Form {
            Section(String(localized: "Task")) {
                Picker(
                    String(localized: "Measurement"),
                    selection: $templateID
                ) {
                    ForEach(
                        AnnotationPresentation
                            .measurementTemplates
                    ) { template in
                        DescribedPickerOption(
                            title: template.title,
                            detail: AnnotationPresentation
                                .measurementTemplateDescription(
                                    id: template.id
                                )
                        )
                        .tag(template.id)
                    }
                }
                .onChange(of: templateID) { _, newID in
                    guard let template =
                        AnnotationPresentation
                            .measurementTemplates
                            .first(where: { $0.id == newID })
                    else {
                        return
                    }
                    if template.id != "custom" {
                        quantityType = template.quantityType
                        unit = template.unit
                    }
                }

                TextField(
                    String(localized: "Value"),
                    text: $valueText
                )
                .decimalKeyboard()

                Picker(
                    String(localized: "Unit"),
                    selection: $unit
                ) {
                    ForEach(
                        [
                            MeasurementUnit.meter,
                            .radian,
                            .dimensionless,
                        ],
                        id: \.self
                    ) { unit in
                        DescribedPickerOption(
                            title: AnnotationPresentation
                                .unitName(unit),
                            detail: AnnotationPresentation
                                .measurementUnitDescription(unit)
                        )
                        .tag(unit)
                    }
                }

                Picker(
                    String(localized: "How measured"),
                    selection: $method
                ) {
                    ForEach(methods, id: \.self) { method in
                        DescribedPickerOption(
                            title: AnnotationPresentation
                                .acquisitionMethodName(method),
                            detail: AnnotationPresentation
                                .acquisitionMethodDescription(
                                    method
                                )
                        )
                        .tag(method)
                    }
                }
            }

            if endpointsVisible {
                Section(
                    String(localized:
                        "Spatial endpoints (optional)")
                ) {
                    EndpointPicker(
                        title: String(localized: "Endpoint A"),
                        selection: $endpointA,
                        candidates: endpointCandidates
                    )
                    EndpointPicker(
                        title: String(localized: "Endpoint B"),
                        selection: $endpointB,
                        candidates: endpointCandidates
                    )
                    Text(
                        "Endpoints bind this measurement to exact staged spatial authorities in the capture coordinate space. A typed-in value stays user-attested — endpoints never imply the value was derived from them."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !endpointA.isEmpty && !endpointB.isEmpty {
                    Section(String(localized: "Derived from endpoints")) {
                        Button(
                            String(localized:
                                "Compute distance from endpoints")
                        ) {
                            deriveDistance()
                        }
                        Text(
                            "Computes the value from accepted endpoint geometry and stores it as a separate derived record — RoomPlan/LiDAR provenance when both endpoints share it, otherwise capture_app_derived."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if editingMeasurement == nil {
                Section(
                    String(localized: "Instrument reading (optional)")
                ) {
                    instrumentImportContent
                }
            }

            Section {
                DisclosureGroup(
                    String(localized: "Advanced"),
                    isExpanded: $showingAdvanced
                ) {
                    TextField(
                        String(localized: "Quantity type"),
                        text: $quantityType
                    )
                    .disabled(templateID != "custom")

                    TextField(
                        String(localized:
                            "Stated uncertainty (optional)"),
                        text: $uncertaintyText
                    )
                    .decimalKeyboard()
                    TextField(
                        String(localized:
                            "Original value text (optional)"),
                        text: $sourceValueText
                    )
                    TextField(
                        String(localized:
                            "Instrument class (optional)"),
                        text: $instrumentClass
                    )
                    TextField(
                        String(localized:
                            "Make/model (optional)"),
                        text: $instrumentModel
                    )
                }
            }

            if !instrumentProfiles.isEmpty {
                Section(
                    String(localized: "Instrument authority")
                ) {
                    Picker(
                        String(localized: "Instrument profile"),
                        selection: $instrumentAuthority
                    ) {
                        DescribedPickerOption(
                            title: String(localized: "None"),
                            detail: String(localized:
                                "Record the measurement without binding it to an instrument profile.")
                        )
                        .tag(
                            MeasurementInstrumentReference?
                                .none
                        )
                        ForEach(
                            instrumentProfiles,
                            id: \.id
                        ) { profile in
                            Text(
                                [
                                    profile.manufacturer,
                                    profile.model,
                                    profile.serialOrAssetID,
                                    "v"
                                        + String(
                                            profile.profileVersion
                                        ),
                                ]
                                .compactMap { $0 }
                                .joined(separator: " ")
                            )
                            .tag(
                                MeasurementInstrumentReference?
                                    .some(profile.reference)
                            )
                        }
                    }
                    Text(
                        "Binds the measurement to the exact instrument profile version + digest — a later recalibration mints a new version and can never rewrite this binding."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if !evidenceFrames.isEmpty || !otherEvidenceRefs.isEmpty {
                EvidenceFramePickerView(
                    frames: evidenceFrames,
                    remainingRefs: otherEvidenceRefs,
                    selectedRefs: $selectedEvidenceRefs
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
                        .foregroundStyle(CaptureColorRole.blocked.color)
                }
            }
        }
        .fileImporter(
            isPresented: $importingInstrumentReading,
            allowedContentTypes: [.json, .text],
            allowsMultipleSelection: false
        ) { result in
            importInstrumentReading(result)
        }
        .navigationTitle(
            editingMeasurement == nil
                ? String(localized: "Add measurement")
                : String(localized: "Edit measurement")
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(
                    editingMeasurement == nil
                        ? String(localized: "Add")
                        : String(localized: "Save")
                ) {
                    save()
                }
            }
        }
    }

    /// The device-reading import flow (issue #226/#355): the
    /// operator describes the instrument, imports the file the
    /// instrument's own tooling produced, reviews the staged reading
    /// — exact received text, unit, device id, calibration — then
    /// explicitly confirms it into a pending measurement. A failed
    /// or stale file never overwrites typed input; the manual path
    /// stays untouched underneath.
    @ViewBuilder
    private var instrumentImportContent: some View {
        Picker(
            String(localized: "Instrument method"),
            selection: $importMethod
        ) {
            ForEach(importMethods, id: \.self) { method in
                DescribedPickerOption(
                    title: AnnotationPresentation
                        .acquisitionMethodName(method),
                    detail: AnnotationPresentation
                        .acquisitionMethodDescription(method)
                )
                .tag(method)
            }
        }
        TextField(
            String(localized: "Instrument make/model"),
            text: $importMakeModel
        )
        Button(
            String(localized: "Import reading file…")
        ) {
            importingInstrumentReading = true
        }
        .disabled(importMakeModel.isEmpty)
        if let pending = instrumentSession.pending {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Staged device reading"))
                    .font(.subheadline.weight(.semibold))
                Text(
                    String(pending.reading.value) + " "
                        + MissionPresentation.measurementUnitSymbol(
                            pending.reading.unit
                        )
                )
                Text(
                    String(
                        format: String(localized: "Received: %@"),
                        pending.reading.receivedValueText
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let deviceID =
                    pending.reading.deviceMeasurementID
                {
                    Text(
                        String(
                            format: String(localized: "Device id: %@"),
                            deviceID
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let observedAt = pending.reading.observedAtUTC {
                    Text(
                        String(
                            format: String(
                                localized: "Observed at: %@"
                            ),
                            observedAt
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let calibration =
                    pending.reading.calibrationStatus
                {
                    Text(
                        String(
                            format: String(
                                localized: "Calibration: %@"
                            ),
                            calibration
                                + (pending.reading.calibrationDate
                                    .map { " · " + $0 } ?? "")
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                HStack {
                    Button(
                        String(localized: "Use this reading")
                    ) {
                        confirmPendingReading()
                    }
                    .buttonStyle(.borderedProminent)
                    Button(
                        String(localized: "Discard")
                    ) {
                        instrumentSession.clearPending()
                    }
                }
            }
            .padding(.vertical, 4)
        }
        Text(
            "Reads a value file exported by the instrument (JSON or \"4.215 m\" text). The reading is staged first — nothing is recorded until you confirm it."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func importInstrumentReading(
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
            let descriptor = try InstrumentAdapterDescriptor(
                adapterID: "file-import",
                acquisitionMethod: importMethod,
                makeModel: importMakeModel,
                transport: "file"
            )
            let adapter = FileImportInstrumentAdapter(
                descriptor: descriptor,
                data: data
            )
            Task {
                // The session is a value type; mutate a copy so the
                // staged write lands after the async adapter call.
                var session = instrumentSession
                do {
                    _ = try await session.stageReading(
                        from: adapter
                    )
                    instrumentSession = session
                    errorText = nil
                } catch {
                    instrumentSession = session
                    errorText = AnnotationPresentation
                        .errorText(error)
                }
            }
        } catch {
            errorText = AnnotationPresentation.errorText(error)
        }
    }

    private func confirmPendingReading() {
        guard let pending = instrumentSession.pending else {
            return
        }
        do {
            let endpoints = try endpointRefs()
            let measurement =
                try instrumentSession.confirmMeasurement(
                    pending,
                    quantityType: quantityType,
                    coordinateSpaceID:
                        endpoints.isEmpty ? nil : coordinateSpaceID,
                    endpointRefs: endpoints,
                    evidenceRefs: selectedEvidenceRefs.sorted()
                )
            onSave(measurement)
            dismiss()
        } catch {
            errorText = AnnotationPresentation.errorText(error)
        }
    }

    /// Endpoint pickers apply to new measurements only — the edit
    /// path never exposes endpoint-backed or derived measurements.
    /// Endpoint count semantics come from the quantity registry
    /// (issue #287): `0` hides the pickers, `2` requires both or
    /// neither, an unregistered quantity leaves endpoints optional.
    private var endpointsVisible: Bool {
        editingMeasurement == nil && !endpointCandidates.isEmpty
            && MeasurementQuantityRegistry
                .definition(for: quantityType)?
                .expectedEndpoints != 0
    }

    private func endpointEntity(_ entityID: String)
        -> CaptureAnnotationEntity?
    {
        endpointCandidates.first {
            $0.entityID.description == entityID
        }
    }

    private func endpointRefs() throws -> [String] {
        if !endpointsVisible {
            return []
        }
        switch (endpointA.isEmpty, endpointB.isEmpty) {
        case (true, true):
            return []
        case (false, false):
            guard endpointA != endpointB else {
                throw MeasurementModelError
                    .duplicateEndpointReference
            }
            return ["entity:" + endpointA, "entity:" + endpointB]
        default:
            throw MeasurementModelError
                .invalidEndpointCountForQuantity
        }
    }

    private func deriveDistance() {
        do {
            guard let entityA = endpointEntity(endpointA),
                  let entityB = endpointEntity(endpointB)
            else {
                throw MeasurementModelError.emptyEndpointReference
            }
            let authorityA = try MeasurementEndpointAuthority(
                entity: entityA
            )
            let authorityB = try MeasurementEndpointAuthority(
                entity: entityB
            )
            let measurement =
                try DerivedMeasurementBuilder.distance(
                    quantityType: quantityType,
                    endpointA: authorityA,
                    endpointB: authorityB,
                    coordinateSpaceID: coordinateSpaceID,
                    observedAtUTC:
                        BundleTimestamp.utcString(from: Date()),
                    evidenceRefs: selectedEvidenceRefs.sorted()
                )
            onSave(measurement)
            dismiss()
        } catch {
            errorText = AnnotationPresentation.errorText(error)
        }
    }

    private func save() {
        do {
            guard let value = Double(valueText), value.isFinite
            else {
                throw MeasurementModelError.invalidScalar
            }

            let uncertainty: Double?
            if uncertaintyText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            {
                uncertainty = nil
            } else {
                guard let parsed = Double(uncertaintyText)
                else {
                    throw MeasurementModelError.negativeUncertainty
                }
                uncertainty = parsed
            }

            let instrument: MeasurementInstrument? =
                if instrumentClass.isEmpty, instrumentModel.isEmpty {
                    nil
                } else {
                    MeasurementInstrument(
                        instrumentClass:
                            instrumentClass.isEmpty
                                ? nil : instrumentClass,
                        makeModel:
                            instrumentModel.isEmpty
                                ? nil : instrumentModel
                    )
                }

            let endpoints = try endpointRefs()
            var measurement: CaptureMeasurement
            if let editingMeasurement {
                measurement =
                    try MeasurementEditSupport
                        .buildEditedMeasurement(
                            seed: MeasurementEditSeed(
                                measurement: editingMeasurement
                            ),
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
            } else {
                measurement =
                    try ManualAuthorityBuilder.scalarMeasurement(
                        quantityType: quantityType,
                        value: value,
                        unit: unit,
                        acquisitionMethod: method,
                        coordinateSpaceID:
                            endpoints.isEmpty ? nil : coordinateSpaceID,
                        endpointRefs: endpoints,
                        instrument: instrument,
                        statedUncertainty: uncertainty,
                        sourceValueText:
                            sourceValueText.isEmpty
                                ? nil : sourceValueText,
                        evidenceRefs:
                            selectedEvidenceRefs.sorted()
                    )
            }
            measurement = try measurement
                .withInstrumentAuthority(instrumentAuthority)
            onSave(measurement)
            dismiss()
        } catch {
            errorText =
                AnnotationPresentation.errorText(error)
        }
    }
}


/// Picker binding a measurement endpoint to a staged entity by exact
/// `entityID` (issue #215).
private struct EndpointPicker: View {
    let title: String
    @Binding var selection: String
    let candidates: [CaptureAnnotationEntity]

    var body: some View {
        Picker(title, selection: $selection) {
            DescribedPickerOption(
                title: String(localized: "None"),
                detail: String(localized:
                    "Leave this endpoint unbound.")
            )
            .tag("")
            ForEach(candidates, id: \.entityID) { entity in
                Text(
                    entity.label + " · "
                        + MissionPresentation.annotationEntityTypeName(
                            entity.type
                        )
                )
                .tag(entity.entityID.description)
            }
        }
    }
}
