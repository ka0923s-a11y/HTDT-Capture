import Foundation
import SwiftUI
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
    @State private var selectedEvidenceRefs: Set<String>
    @State private var endpointA = ""
    @State private var endpointB = ""
    @State private var showingAdvanced = false
    @State private var errorText: String?

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

    public init(
        editingMeasurement: CaptureMeasurement? = nil,
        coordinateSpaceID: CoordinateSpaceID,
        endpointCandidates: [CaptureAnnotationEntity] = [],
        evidenceFrames: [EvidenceFramePresentation] = [],
        otherEvidenceRefs: [String] = [],
        onSave: @escaping (CaptureMeasurement) -> Void
    ) {
        self.editingMeasurement = editingMeasurement
        self.coordinateSpaceID = coordinateSpaceID
        self.endpointCandidates = endpointCandidates
        self.evidenceFrames = evidenceFrames
        self.otherEvidenceRefs = otherEvidenceRefs
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
                        Text(template.title).tag(template.id)
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
                        Text(
                            AnnotationPresentation
                                .unitName(unit)
                        )
                        .tag(unit)
                    }
                }

                Picker(
                    String(localized: "How measured"),
                    selection: $method
                ) {
                    ForEach(methods, id: \.self) { method in
                        Text(
                            AnnotationPresentation
                                .acquisitionMethodName(method)
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
                        .foregroundStyle(.red)
                }
            }
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
            let measurement: CaptureMeasurement
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
            Text(String(localized: "None")).tag("")
            ForEach(candidates, id: \.entityID) { entity in
                Text(entity.label + " · " + entity.type.rawValue)
                    .tag(entity.entityID.description)
            }
        }
    }
}
