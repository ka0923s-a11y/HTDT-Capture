import Foundation
import SwiftUI
import HTDTCaptureCore

public struct CaptureAnnotationWorkspaceView: View {
    public let coordinateSpaceID: CoordinateSpaceID
    public let onCommit: (
        [CaptureAnnotationEntity],
        [CaptureMeasurement]
    ) -> Void
    public let onCancel: () -> Void

    @State private var annotations: [CaptureAnnotationEntity] = []
    @State private var measurements: [CaptureMeasurement] = []
    @State private var addingAnnotation = false
    @State private var addingMeasurement = false

    public init(
        coordinateSpaceID: CoordinateSpaceID,
        onCommit: @escaping (
            [CaptureAnnotationEntity],
            [CaptureMeasurement]
        ) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.coordinateSpaceID = coordinateSpaceID
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public var body: some View {
        List {
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
                Button("Save annotation authority") {
                    onCommit(annotations, measurements)
                }
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
            } footer: {
                Text(
                    "Save writes the canonical annotation and measurement "
                    + "collections once. Edit or delete staged records before "
                    + "saving."
                )
            }
        }
        .sheet(isPresented: $addingAnnotation) {
            NavigationStack {
                ManualAnnotationForm(
                    coordinateSpaceID: coordinateSpaceID
                ) { entity in
                    annotations.append(entity)
                }
            }
        }
        .sheet(isPresented: $addingMeasurement) {
            NavigationStack {
                ManualMeasurementForm { measurement in
                    measurements.append(measurement)
                }
            }
        }
    }

    private func annotationDetail(
        _ entity: CaptureAnnotationEntity
    ) -> String {
        if let role = entity.channelRole {
            return entity.type.rawValue + " · " + role.rawValue
        }
        return entity.type.rawValue
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

    @State private var errorText: String?

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
                TextField("Label", text: $label)
            }

            Section("Position in capture world (m)") {
                TextField("X", text: $xText)
                TextField("Y", text: $yText)
                TextField("Z", text: $zText)
            }

            if type == .speaker {
                Section("Speaker orientation") {
                    TextField(
                        "Channel role (L, C, R, ...)",
                        text: $channelRole
                    )
                    TextField(
                        "Yaw degrees (0 = -Z, 90 = +X)",
                        text: $yawText
                    )
                }
            }

            Section("Pinned HTDT equipment authority") {
                Toggle(
                    "Attach equipment reference",
                    isOn: $includeEquipmentReference
                )
                if includeEquipmentReference {
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
                    Text(
                        "All three values are required. The capture app "
                        + "does not guess an equipment revision."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    equipmentHash: digest
                )
            } else {
                equipment = nil
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
                equipmentReference: equipment
            )
            onAdd(entity)
            dismiss()
        } catch {
            errorText = String(describing: error)
        }
    }
}

private struct ManualMeasurementForm: View {
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
    @State private var errorText: String?

    private let units: [MeasurementUnit] = [
        .meter,
        .radian,
        .dimensionless,
    ]
    private let methods: [MeasurementAcquisitionMethod] = [
        .tapeMeasure,
        .laserDistanceMeter,
        .manufacturerSpecification,
        .lidarDerived,
        .roomPlanDerived,
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
                    "Manual entries are persisted as user-attested "
                    + "measurements; derived LiDAR/RoomPlan values should use "
                    + "their dedicated evidence path instead."
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
                        ? nil : sourceValueText
                )
            onAdd(measurement)
            dismiss()
        } catch {
            errorText = String(describing: error)
        }
    }
}
