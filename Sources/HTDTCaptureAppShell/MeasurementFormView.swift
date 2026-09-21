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
        evidenceFrames: [EvidenceFramePresentation] = [],
        otherEvidenceRefs: [String] = [],
        onSave: @escaping (CaptureMeasurement) -> Void
    ) {
        self.editingMeasurement = editingMeasurement
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
