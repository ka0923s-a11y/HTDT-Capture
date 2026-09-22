import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HTDTCaptureCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Shared presentation names for the field-authority enums.
public enum FieldAuthorityPresentation {
    public static func evidenceKindName(
        _ kind: FieldEvidenceKind
    ) -> String {
        switch kind {
        case .installationPhoto:
            return String(localized: "Installation photo")
        case .dimensionVerification:
            return String(localized: "Dimension verification")
        case .equipmentIdentity:
            return String(localized: "Equipment identity")
        case .routingVerification:
            return String(localized: "Routing verification")
        case .microphoneSetup:
            return String(localized: "Microphone setup")
        case .treatmentInstallation:
            return String(localized: "Treatment installation")
        case .generalNote:
            return String(localized: "General note")
        case .externalDocument:
            return String(localized: "External document")
        }
    }

    public static func instrumentClassName(
        _ instrumentClass: MeasurementInstrumentClass
    ) -> String {
        switch instrumentClass {
        case .tapeMeasure:
            return String(localized: "Tape measure")
        case .laserDistanceMeter:
            return String(localized: "Laser distance meter")
        case .measurementMicrophone:
            return String(localized: "Measurement microphone")
        case .splMeter:
            return String(localized: "SPL meter")
        case .microphoneCalibrator:
            return String(localized: "Microphone calibrator")
        case .audioAnalyzer:
            return String(localized: "Audio analyzer")
        case .thermometer:
            return String(localized: "Thermometer")
        case .hygrometer:
            return String(localized: "Hygrometer")
        case .levelInstrument:
            return String(localized: "Level")
        case .scale:
            return String(localized: "Scale")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func calibrationStateName(
        _ state: InstrumentCalibrationState
    ) -> String {
        switch state {
        case .calibrated:
            return String(localized: "Calibrated")
        case .uncalibrated:
            return String(localized: "Uncalibrated")
        case .expired:
            return String(localized: "Expired")
        case .notApplicable:
            return String(localized: "Not applicable")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    public static func calibrationEvidenceKindName(
        _ kind: CalibrationEvidenceKind
    ) -> String {
        switch kind {
        case .calibrationCertificate:
            return String(localized: "Calibration certificate")
        case .microphoneCalibrationFile:
            return String(localized: "Microphone calibration file")
        case .manufacturerRecord:
            return String(localized: "Manufacturer record")
        case .userAttestation:
            return String(localized: "User attestation")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func settingParameterName(
        _ parameter: ObservedSettingParameter
    ) -> String {
        switch parameter {
        case .channelGain:
            return String(localized: "Channel gain")
        case .channelDelay:
            return String(localized: "Channel delay")
        case .channelDistance:
            return String(localized: "Channel distance")
        case .crossoverFrequency:
            return String(localized: "Crossover frequency")
        case .polarity:
            return String(localized: "Polarity")
        case .speakerSize:
            return String(localized: "Speaker size")
        case .bassManagement:
            return String(localized: "Bass management")
        case .peqBandFrequency:
            return String(localized: "PEQ band frequency")
        case .peqBandGain:
            return String(localized: "PEQ band gain")
        case .peqBandQ:
            return String(localized: "PEQ band Q")
        case .peqEnabled:
            return String(localized: "PEQ enabled")
        case .dspPreset:
            return String(localized: "DSP preset")
        case .dspMode:
            return String(localized: "DSP mode")
        case .processorPreset:
            return String(localized: "Processor preset")
        case .processorMode:
            return String(localized: "Processor mode")
        case .subwooferGain:
            return String(localized: "Subwoofer gain")
        case .subwooferPhase:
            return String(localized: "Subwoofer phase")
        case .subwooferCrossover:
            return String(localized: "Subwoofer crossover")
        case .subwooferPolarity:
            return String(localized: "Subwoofer polarity")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func settingStateName(
        _ state: ObservedSettingState
    ) -> String {
        switch state {
        case .observed:
            return String(localized: "Observed")
        case .unknown:
            return String(localized: "Unknown")
        case .notApplicable:
            return String(localized: "Not applicable")
        }
    }

    public static func terminationKindName(
        _ kind: WiringTerminationKind
    ) -> String {
        switch kind {
        case .speaker:
            return String(localized: "Speaker")
        case .subwoofer:
            return String(localized: "Subwoofer")
        case .avReceiver:
            return String(localized: "AV receiver")
        case .processor:
            return String(localized: "Processor")
        case .amplifier:
            return String(localized: "Amplifier")
        case .projector:
            return String(localized: "Projector")
        case .display:
            return String(localized: "Display")
        case .rack:
            return String(localized: "Rack")
        case .wallPlate:
            return String(localized: "Wall plate")
        case .servicePoint:
            return String(localized: "Service point")
        case .other:
            return String(localized: "Other")
        }
    }

    public static func segmentObservationName(
        _ observation: WiringSegmentObservation
    ) -> String {
        switch observation {
        case .observed:
            return String(localized: "Observed")
        case .estimated:
            return String(localized: "Estimated")
        case .hiddenUnknown:
            return String(localized: "Hidden (unknown)")
        }
    }

    public static func routeStateName(_ state: WiringRouteState)
        -> String
    {
        switch state {
        case .planned:
            return String(localized: "Planned")
        case .estimated:
            return String(localized: "Estimated")
        case .observedAsBuilt:
            return String(localized: "Observed as-built")
        }
    }

    public static func targetRefLabel(
        _ ref: String,
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement]
    ) -> String {
        if ref.hasPrefix("entity:") {
            let id = String(ref.dropFirst("entity:".count))
            if let entity = annotations.first(where: {
                $0.entityID.description == id
            }) {
                return entity.label
            }
        }
        if ref.hasPrefix("measurement:") {
            let id = String(ref.dropFirst("measurement:".count))
            if let measurement = measurements.first(where: {
                $0.measurementID.description == id
            }) {
                return AnnotationPresentation
                    .measurementTitle(
                        forQuantityType: measurement.quantityType
                    )
            }
        }
        return ref
    }
}

/// Operator profiles (issue #310): app-local, revocable-by-absence
/// identities. No account, no sign-in — a display name plus optional
/// organization/role, bound to this revision.
public struct OperatorProfilesView: View {
    @Binding public var operators: [OperatorProfile]
    @Binding public var selectedOperatorID: OperatorProfileID?
    public let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var organization = ""
    @State private var role = ""
    @State private var errorText: String?

    public init(
        operators: Binding<[OperatorProfile]>,
        selectedOperatorID: Binding<OperatorProfileID?>,
        onChange: @escaping () -> Void = {}
    ) {
        self._operators = operators
        self._selectedOperatorID = selectedOperatorID
        self.onChange = onChange
    }

    public var body: some View {
        Form {
            Section(
                String(localized: "Author identity (optional)")
            ) {
                Picker(
                    String(localized: "Author as"),
                    selection: $selectedOperatorID
                ) {
                    Text(String(localized: "Anonymous"))
                        .tag(OperatorProfileID?.none)
                    ForEach(operators, id: \.operatorID) { profile in
                        Text(profile.displayName)
                            .tag(OperatorProfileID?.some(
                                profile.operatorID
                            ))
                    }
                }
                .onChange(of: selectedOperatorID) { _, _ in
                    onChange()
                }
                Text(
                    "The selected identity is stamped onto new annotations, measurements and field evidence. It is stored with the capture and shown in Review before export."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(String(localized: "Operator profiles")) {
                if operators.isEmpty {
                    Text(
                        String(localized:
                            "No operator profiles yet.")
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(operators, id: \.operatorID) { profile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName)
                            Text(
                                [
                                    profile.organization,
                                    profile.role,
                                ]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(String(localized: "Add operator")) {
                TextField(
                    String(localized: "Display name"),
                    text: $displayName
                )
                TextField(
                    String(localized:
                        "Organization (optional)"),
                    text: $organization
                )
                TextField(
                    String(localized: "Role (optional)"),
                    text: $role
                )
                Button(String(localized: "Add profile")) {
                    addProfile()
                }
                .disabled(
                    displayName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(String(localized: "Operators"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done")) { dismiss() }
            }
        }
    }

    private func addProfile() {
        do {
            let profile = try OperatorProfile(
                displayName: displayName,
                organization: organization.isEmpty
                    ? nil : organization,
                role: role.isEmpty ? nil : role
            )
            operators.append(profile)
            selectedOperatorID = profile.operatorID
            displayName = ""
            organization = ""
            role = ""
            errorText = nil
            onChange()
        } catch {
            errorText = AnnotationPresentation.errorText(error)
        }
    }
}

/// Field-evidence capture form (issues #300/#314): a typed record
/// bound to the exact item that triggered it, with an asset that is
/// either a linked scan frame (bytes shared, never duplicated), a
/// freshly captured close-up photo (preview + retake before commit),
/// or an imported external document kept byte-exact.
public struct FieldEvidenceFormView: View {
    public let captureRevisionID: CaptureRevisionID
    /// Binding refs the record is prefilled with — the triggering
    /// entity/measurement plus the task scope, if any (#314).
    public let initialTargets: [String]
    public let annotations: [CaptureAnnotationEntity]
    public let measurements: [CaptureMeasurement]
    public let evidenceFrames: [EvidenceFramePresentation]
    public let taskScopeRefs: [String]
    /// Captures a new close-up photo; returns raw bytes + metadata.
    public let captureFieldEvidencePhoto:
        () async throws -> CapturedFieldPhoto
    public let onCommit:
        (FieldEvidenceRecord, StagedFieldAsset?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var evidenceID = FieldEvidenceID()
    @State private var kind: FieldEvidenceKind = .installationPhoto
    @State private var title = ""
    @State private var note = ""
    @State private var extraTargets: Set<String> = []
    @State private var assetChoice = 0 // 0 none, 1 close-up, 2 import, 3 frame
    @State private var linkedFrameRef = ""
    @State private var capturedPhoto: CapturedFieldPhoto?
    @State private var importedData: Data?
    @State private var importedName = ""
    @State private var importedMediaType:
        FieldEvidenceMediaType = .jpeg
    @State private var importingDocument = false
    @State private var capturingPhoto = false
    @State private var showObserved = false
    @State private var observedValueText = ""
    @State private var observedNote = ""
    @State private var observedUnit: MeasurementUnit = .meter
    @State private var selectedOperatorID: OperatorProfileID?
    @State private var errorText: String?

    public init(
        captureRevisionID: CaptureRevisionID,
        initialTargets: [String],
        annotations: [CaptureAnnotationEntity] = [],
        measurements: [CaptureMeasurement] = [],
        evidenceFrames: [EvidenceFramePresentation] = [],
        taskScopeRefs: [String] = [],
        selectedOperatorID: OperatorProfileID? = nil,
        captureFieldEvidencePhoto: @escaping
            () async throws -> CapturedFieldPhoto,
        onCommit: @escaping
            (FieldEvidenceRecord, StagedFieldAsset?) -> Void
    ) {
        self.captureRevisionID = captureRevisionID
        self.initialTargets = initialTargets
        self.annotations = annotations
        self.measurements = measurements
        self.evidenceFrames = evidenceFrames
        self.taskScopeRefs = taskScopeRefs
        self.captureFieldEvidencePhoto = captureFieldEvidencePhoto
        self.onCommit = onCommit
        _selectedOperatorID = State(
            initialValue: selectedOperatorID
        )
    }

    private var allTargets: [String] {
        var targets = Set(initialTargets + taskScopeRefs)
        targets.formUnion(extraTargets)
        return targets.sorted()
    }

    public var body: some View {
        Form {
            Section(String(localized: "Evidence")) {
                Picker(
                    String(localized: "Kind"),
                    selection: $kind
                ) {
                    ForEach(
                        FieldEvidenceKind.allCases,
                        id: \.self
                    ) { value in
                        Text(
                            FieldAuthorityPresentation
                                .evidenceKindName(value)
                        )
                        .tag(value)
                    }
                }
                TextField(
                    String(localized: "Title"),
                    text: $title
                )
                TextField(
                    String(localized: "Note (optional)"),
                    text: $note,
                    axis: .vertical
                )
            }

            Section(
                String(localized: "Bound to")
            ) {
                ForEach(allTargets, id: \.self) { ref in
                    Text(
                        FieldAuthorityPresentation
                            .targetRefLabel(
                                ref,
                                annotations: annotations,
                                measurements: measurements
                            )
                    )
                    .font(.caption.monospaced())
                }
                ForEach(annotations, id: \.entityID) { entity in
                    let ref = "entity:" + entity.entityID.description
                    if !allTargets.contains(ref) {
                        Button(entity.label) {
                            extraTargets.insert(ref)
                        }
                    }
                }
            }

            Section(String(localized: "Asset")) {
                Picker(
                    String(localized: "Asset"),
                    selection: $assetChoice
                ) {
                    Text(String(localized: "No asset"))
                        .tag(0)
                    Text(
                        String(localized:
                            "Capture close-up photo")
                    )
                    .tag(1)
                    Text(
                        String(localized: "Import document")
                    )
                    .tag(2)
                    if !evidenceFrames.isEmpty {
                        Text(
                            String(localized:
                                "Link existing scan frame")
                        )
                        .tag(3)
                    }
                }
                switch assetChoice {
                case 1:
                    capturedPhotoSection
                case 2:
                    importedDocumentSection
                case 3:
                    linkedFrameSection
                default:
                    Text(
                        "Text-only evidence; no binary asset is stored."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                DisclosureGroup(
                    String(localized:
                        "Explicitly observed value (optional)"),
                    isExpanded: $showObserved
                ) {
                    TextField(
                        String(localized: "Observed value"),
                        text: $observedValueText
                    )
                    .decimalKeyboard()
                    Picker(
                        String(localized: "Unit"),
                        selection: $observedUnit
                    ) {
                        ForEach(
                            [
                            MeasurementUnit.meter,
                            .radian,
                            .dimensionless,
                            .second,
                            .degreeCelsius,
                            .percent,
                        ],
                            id: \.self
                        ) { unit in
                            Text(
                                MissionPresentation.measurementUnitSymbol(
                                    unit
                                )
                            ).tag(unit)
                        }
                    }
                    TextField(
                        String(localized:
                            "Observed text (non-numeric)"),
                        text: $observedNote
                    )
                }
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(
            String(localized: "Capture evidence")
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Save")) { save() }
                    .disabled(
                        title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                            || capturingPhoto
                    )
            }
        }
        .fileImporter(
            isPresented: $importingDocument,
            allowedContentTypes: [
                .image, .pdf, .data,
            ],
            allowsMultipleSelection: false
        ) { result in
            importDocument(result)
        }
    }

    @ViewBuilder
    private var capturedPhotoSection: some View {
        if let photo = capturedPhoto {
            fieldPhotoPreview(photo)
            Text(
                String(format: "%d × %d", photo.pixelWidth,
                       photo.pixelHeight)
                + " · HEIC · "
                + String(photo.data.count)
                + " bytes"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button(String(localized: "Retake")) {
                capturePhoto()
            }
        } else {
            Button(
                capturingPhoto
                    ? String(localized: "Capturing…")
                    : String(localized: "Capture photo")
            ) {
                capturePhoto()
            }
            .disabled(capturingPhoto)
            Text(
                "Captures a dedicated close-up from the camera now — no scanning restart. It is stored as image evidence only, with no spatial authority."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func fieldPhotoPreview(
        _ photo: CapturedFieldPhoto
    ) -> some View {
        #if canImport(UIKit)
        if let image = UIImage(data: photo.data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 220)
        }
        #elseif canImport(AppKit)
        if let image = NSImage(data: photo.data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 220)
        }
        #endif
    }

    private var importedSummary: String {
        importedName + " · " + importedMediaType.rawValue
            + " · " + String(importedData?.count ?? 0)
            + " bytes"
    }

    @ViewBuilder
    private var importedDocumentSection: some View {
        if importedData != nil {
            Text(importedSummary).font(.caption)
        }
        Button(
            importedData == nil
                ? String(localized: "Choose document")
                : String(localized: "Replace document")
        ) {
            importingDocument = true
        }
        Text(
            "The file is stored verbatim with its exact SHA-256 and media type."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var linkedFrameSection: some View {
        Picker(
            String(localized: "Scan frame"),
            selection: $linkedFrameRef
        ) {
            Text(String(localized: "Select a frame"))
                .tag("")
            ForEach(evidenceFrames, id: \.reference) { frame in
                Text(frame.reference).tag(frame.reference)
            }
        }
        Text(
            "Links the existing canonical scan frame — its bytes are shared, not duplicated."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func capturePhoto() {
        capturingPhoto = true
        errorText = nil
        Task { @MainActor in
            do {
                capturedPhoto = try await captureFieldEvidencePhoto()
            } catch {
                errorText =
                    AnnotationPresentation.errorText(error)
            }
            capturingPhoto = false
        }
    }

    private func importDocument(
        _ result: Result<[URL], Error>
    ) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let accessing =
                url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            importedData = data
            importedName = url.lastPathComponent
            importedMediaType = Self.mediaType(for: url)
            errorText = nil
        } catch {
            errorText =
                AnnotationPresentation.errorText(error)
        }
    }

    static func mediaType(
        for url: URL
    ) -> FieldEvidenceMediaType {
        switch url.pathExtension.lowercased() {
        case "heic", "heif":
            return .heic
        case "jpg", "jpeg":
            return .jpeg
        case "png":
            return .png
        case "pdf":
            return .pdf
        default:
            return .binary
        }
    }

    private func save() {
        do {
            var asset: FieldEvidenceAsset?
            var stagedAsset: StagedFieldAsset?
            switch assetChoice {
            case 1:
                guard let photo = capturedPhoto else {
                    throw FieldAuthorityModelError
                        .missingAssetAuthority
                }
                let path =
                    FieldEvidenceAssetPaths.captured(
                        evidenceID: evidenceID,
                        mediaType: photo.mediaType
                    )
                asset = try FieldEvidenceAsset.capturedPhoto(
                    assetPath: path,
                    sha256: EvidenceIntegrity.sha256(
                        of: photo.data
                    ),
                    mediaType: photo.mediaType,
                    pixelWidth: photo.pixelWidth,
                    pixelHeight: photo.pixelHeight
                )
                stagedAsset = StagedFieldAsset(
                    path: path,
                    data: photo.data
                )
            case 2:
                guard let data = importedData else {
                    throw FieldAuthorityModelError
                        .missingAssetAuthority
                }
                let path =
                    FieldEvidenceAssetPaths.imported(
                        evidenceID: evidenceID,
                        mediaType: importedMediaType
                    )
                asset = try FieldEvidenceAsset.importedFile(
                    assetPath: path,
                    sha256: EvidenceIntegrity.sha256(
                        of: data
                    ),
                    mediaType: importedMediaType,
                    originalFilename: importedName
                )
                stagedAsset = StagedFieldAsset(
                    path: path,
                    data: data
                )
            case 3:
                guard !linkedFrameRef.isEmpty else {
                    throw FieldAuthorityModelError
                        .missingAssetAuthority
                }
                asset = try FieldEvidenceAsset.canonicalFrame(
                    frameRef: linkedFrameRef
                )
            default:
                asset = nil
            }

            var observedValue: Double?
            var observedUnit: MeasurementUnit?
            var observedText: String?
            if showObserved {
                let trimmed = observedValueText
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                if !trimmed.isEmpty {
                    guard let parsed = Double(trimmed),
                          parsed.isFinite
                    else {
                        throw FieldAuthorityModelError
                            .invalidObservedValue
                    }
                    observedValue = parsed
                    observedUnit = observedUnitValue
                }
                let trimmedText = observedNote
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                if !trimmedText.isEmpty {
                    observedText = trimmedText
                }
            }

            let record = try FieldEvidenceRecord(
                evidenceID: evidenceID,
                kind: kind,
                title: title,
                note: note.isEmpty ? nil : note,
                targetRefs: allTargets,
                asset: asset,
                captureRevisionID: captureRevisionID,
                operatorID: selectedOperatorID,
                observedValue: observedValue,
                observedUnit: observedUnit,
                observedValueText: observedText
            )
            onCommit(record, stagedAsset)
            dismiss()
        } catch {
            errorText =
                AnnotationPresentation.errorText(error)
        }
    }

    private var observedUnitValue: MeasurementUnit { observedUnit }
}

/// Instrument profile form (issue #331): creates a new immutable
/// profile version for an instrument — exact device identity,
/// calibration state/dates, and an exact calibration evidence
/// reference. Editing an existing instrument mints
/// `profile_version + 1`; committed measurements keep naming the
/// version they bound.
public struct InstrumentProfileFormView: View {
    private let existing: MeasurementInstrumentProfile?
    private let nextVersion: Int
    public let onCommit: (MeasurementInstrumentProfile) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var instrumentClass:
        MeasurementInstrumentClass
    @State private var manufacturer: String
    @State private var model: String
    @State private var serial: String
    @State private var calibrationState:
        InstrumentCalibrationState
    @State private var calibrationDate: String
    @State private var calibrationValidUntil: String
    @State private var evidenceKind:
        CalibrationEvidenceKind
    @State private var evidenceRefText: String
    @State private var evidenceRefs: [String]
    @State private var statedAccuracy: String
    @State private var operatorLabel: String
    @State private var errorText: String?

    public init(
        existing: MeasurementInstrumentProfile? = nil,
        onCommit: @escaping
            (MeasurementInstrumentProfile) -> Void
    ) {
        self.existing = existing
        self.nextVersion = (existing?.profileVersion ?? 0) + 1
        self.onCommit = onCommit
        _instrumentClass = State(
            initialValue: existing?.instrumentClass
                ?? .laserDistanceMeter
        )
        _manufacturer = State(
            initialValue: existing?.manufacturer ?? ""
        )
        _model = State(initialValue: existing?.model ?? "")
        _serial = State(
            initialValue: existing?.serialOrAssetID ?? ""
        )
        _calibrationState = State(
            initialValue: existing?.calibrationState ?? .unknown
        )
        _calibrationDate = State(
            initialValue: existing?.calibrationDate ?? ""
        )
        _calibrationValidUntil = State(
            initialValue: existing?.calibrationValidUntil ?? ""
        )
        _evidenceKind = State(
            initialValue: existing?.calibrationEvidenceKind
                ?? .calibrationCertificate
        )
        _evidenceRefText = State(initialValue: "")
        _evidenceRefs = State(
            initialValue: existing?.calibrationEvidenceRefs
                ?? []
        )
        _statedAccuracy = State(
            initialValue: existing?.statedAccuracy ?? ""
        )
        _operatorLabel = State(
            initialValue: existing?.operatorLabel ?? ""
        )
    }

    public var body: some View {
        Form {
            Section(
                String(localized: "Instrument identity")
            ) {
                Picker(
                    String(localized: "Instrument class"),
                    selection: $instrumentClass
                ) {
                    ForEach(
                        MeasurementInstrumentClass.allCases,
                        id: \.self
                    ) { value in
                        Text(
                            FieldAuthorityPresentation
                                .instrumentClassName(value)
                        )
                        .tag(value)
                    }
                }
                TextField(
                    String(localized:
                        "Manufacturer (optional)"),
                    text: $manufacturer
                )
                TextField(
                    String(localized: "Model"),
                    text: $model
                )
                TextField(
                    String(localized:
                        "Serial / asset ID (optional)"),
                    text: $serial
                )
                TextField(
                    String(localized:
                        "Operator label (optional)"),
                    text: $operatorLabel
                )
            }

            Section(String(localized: "Calibration")) {
                Picker(
                    String(localized: "Calibration state"),
                    selection: $calibrationState
                ) {
                    ForEach(
                        InstrumentCalibrationState
                            .allCases,
                        id: \.self
                    ) { state in
                        Text(
                            FieldAuthorityPresentation
                                .calibrationStateName(state)
                        )
                        .tag(state)
                    }
                }
                TextField(
                    String(localized:
                        "Calibration date (YYYY-MM-DD)"),
                    text: $calibrationDate
                )
                TextField(
                    String(localized:
                        "Valid until (YYYY-MM-DD, optional)"),
                    text: $calibrationValidUntil
                )
                Picker(
                    String(localized: "Calibration evidence"),
                    selection: $evidenceKind
                ) {
                    ForEach(
                        CalibrationEvidenceKind.allCases,
                        id: \.self
                    ) { value in
                        Text(
                            FieldAuthorityPresentation
                                .calibrationEvidenceKindName(
                                    value
                                )
                        )
                        .tag(value)
                    }
                }
                ForEach(evidenceRefs, id: \.self) { ref in
                    Text(ref).font(.caption.monospaced())
                }
                .onDelete { evidenceRefs.remove(atOffsets: $0) }
                HStack {
                    TextField(
                        String(localized:
                            "Evidence ref (field_evidence:, path:, frame:, sha256:)"),
                        text: $evidenceRefText
                    )
                    .noAutocapitalization()
                    Button(String(localized: "Add")) {
                        let ref = evidenceRefText
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        if !ref.isEmpty,
                           !evidenceRefs.contains(ref)
                        {
                            evidenceRefs.append(ref)
                            evidenceRefText = ""
                        }
                    }
                    .disabled(evidenceRefText.isEmpty)
                }
                TextField(
                    String(localized:
                        "Stated accuracy (optional, e.g. ±0.5 dB)"),
                    text: $statedAccuracy
                )
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(
            existing == nil
                ? String(localized: "Add instrument")
                : String(localized: "New instrument version")
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Save")) { save() }
                    .disabled(
                        model.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
            }
        }
    }

    private func save() {
        do {
            let profile = try MeasurementInstrumentProfile(
                instrumentID: existing?.instrumentID
                    ?? InstrumentProfileID(),
                profileVersion: nextVersion,
                instrumentClass: instrumentClass,
                manufacturer: manufacturer.isEmpty
                    ? nil : manufacturer,
                model: model,
                serialOrAssetID: serial.isEmpty
                    ? nil : serial,
                calibrationState: calibrationState,
                calibrationDate: calibrationDate.isEmpty
                    ? nil : calibrationDate,
                calibrationValidUntil:
                    calibrationValidUntil.isEmpty
                        ? nil : calibrationValidUntil,
                calibrationEvidenceKind:
                    calibrationState == .unknown
                        || calibrationState == .notApplicable
                        ? nil : evidenceKind,
                calibrationEvidenceRefs: evidenceRefs,
                statedAccuracy: statedAccuracy.isEmpty
                    ? nil : statedAccuracy,
                operatorLabel: operatorLabel.isEmpty
                    ? nil : operatorLabel
            )
            onCommit(profile)
            dismiss()
        } catch {
            errorText =
                AnnotationPresentation.errorText(error)
        }
    }
}

/// Installed-settings observation form (issue #301): a commissioning
/// record of the effective AVR/DSP/processor/subwoofer settings the
/// operator read off the device, bound to the exact device authority.
/// Expected values come from the plan when one supplies them; explicit
/// deviations must name a reason or evidence.
public struct SettingsObservationFormView: View {
    public let captureRevisionID: CaptureRevisionID
    public let annotations: [CaptureAnnotationEntity]
    public let inventoryItems: [SystemInventoryItem]
    public let evidenceRefSuggestions: [String]
    public let selectedOperatorID: OperatorProfileID?
    public let onCommit:
        (InstalledSettingsObservation) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var targetRef = ""
    @State private var settings: [ObservedSettingDraft] = []
    @State private var notes = ""
    @State private var evidenceRefs: [String] = []
    @State private var evidenceRefText = ""
    @State private var editingSetting =
        ObservedSettingDraft()
    @State private var addingSetting = false
    @State private var errorText: String?

    public init(
        captureRevisionID: CaptureRevisionID,
        annotations: [CaptureAnnotationEntity] = [],
        inventoryItems: [SystemInventoryItem] = [],
        evidenceRefSuggestions: [String] = [],
        selectedOperatorID: OperatorProfileID? = nil,
        onCommit: @escaping
            (InstalledSettingsObservation) -> Void
    ) {
        self.captureRevisionID = captureRevisionID
        self.annotations = annotations
        self.inventoryItems = inventoryItems
        self.evidenceRefSuggestions = evidenceRefSuggestions
        self.selectedOperatorID = selectedOperatorID
        self.onCommit = onCommit
    }

    private var targetOptions: [(ref: String, label: String)] {
        var options: [(String, String)] = []
        for item in inventoryItems {
            options.append((
                "inventory_item:" + item.itemID.description,
                item.userLabel
            ))
        }
        for entity in annotations {
            options.append((
                "entity:" + entity.entityID.description,
                entity.label
            ))
        }
        return options
    }

    public var body: some View {
        Form {
            Section(
                String(localized: "Device under observation")
            ) {
                Picker(
                    String(localized: "Target"),
                    selection: $targetRef
                ) {
                    Text(String(localized: "Select target"))
                        .tag("")
                    ForEach(targetOptions, id: \.ref) { option in
                        Text(option.label).tag(option.ref)
                    }
                }
            }

            Section(String(localized: "Settings")) {
                if settings.isEmpty {
                    Text(
                        String(localized:
                            "No settings recorded yet.")
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(settings) { draft in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(draft.summary)
                                .font(.callout)
                            Text(draft.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete {
                        settings.remove(atOffsets: $0)
                    }
                }
                Button(
                    String(localized: "Add setting")
                ) {
                    editingSetting = ObservedSettingDraft()
                    addingSetting = true
                }
            }

            Section(String(localized: "Evidence refs")) {
                ForEach(evidenceRefs, id: \.self) { ref in
                    Text(ref).font(.caption.monospaced())
                }
                .onDelete {
                    evidenceRefs.remove(atOffsets: $0)
                }
                ForEach(
                    evidenceRefSuggestions,
                    id: \.self
                ) { suggestion in
                    if !evidenceRefs.contains(suggestion) {
                        Button(suggestion) {
                            evidenceRefs.append(suggestion)
                        }
                        .font(.caption.monospaced())
                    }
                }
                HStack {
                    TextField(
                        String(localized: "Add ref"),
                        text: $evidenceRefText
                    )
                    .noAutocapitalization()
                    Button(String(localized: "Add")) {
                        let ref = evidenceRefText
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        if !ref.isEmpty,
                           !evidenceRefs.contains(ref)
                        {
                            evidenceRefs.append(ref)
                            evidenceRefText = ""
                        }
                    }
                    .disabled(evidenceRefText.isEmpty)
                }
            }

            Section(String(localized: "Notes")) {
                TextField(
                    String(localized:
                        "Observation notes (optional)"),
                    text: $notes,
                    axis: .vertical
                )
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(
            String(localized: "Record device settings")
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Save")) { save() }
                    .disabled(
                        targetRef.isEmpty || settings.isEmpty
                    )
            }
        }
        .sheet(isPresented: $addingSetting) {
            NavigationStack {
                ObservedSettingFormView(
                    draft: $editingSetting,
                    onDone: {
                        settings.append(editingSetting)
                        addingSetting = false
                    }
                )
            }
        }
    }

    private func save() {
        do {
            let observation = try InstalledSettingsObservation(
                captureRevisionID: captureRevisionID,
                targetRef: targetRef,
                operatorID: selectedOperatorID,
                settings: settings.map { try $0.asModel },
                evidenceRefs: evidenceRefs,
                notes: notes.isEmpty ? nil : notes
            )
            onCommit(observation)
            dismiss()
        } catch {
            errorText =
                AnnotationPresentation.errorText(error)
        }
    }
}

/// Editable draft of one observed setting before it is validated into
/// an `ObservedSetting` (issue #301).
public struct ObservedSettingDraft: Identifiable, Sendable {
    public let id = UUID()
    public var parameter: ObservedSettingParameter = .channelGain
    public var customParameter = ""
    public var scope = ""
    public var state: ObservedSettingState = .observed
    public var valueNumberText = ""
    public var valueText = ""
    public var unitText = ""
    public var expectedNumberText = ""
    public var expectedText = ""
    public var expectedUnitText = ""
    public var expectedSourceRef = ""
    public var deviates = false
    public var deviationReason = ""
    public var evidenceRefs: [String] = []

    public init() {}

    public var summary: String {
        let name = parameter == .other
            ? customParameter
            : FieldAuthorityPresentation
                .settingParameterName(parameter)
        return scope.isEmpty ? name : name + " · " + scope
    }

    public var detail: String {
        var parts = [
            FieldAuthorityPresentation.settingStateName(state)
        ]
        if !valueNumberText.isEmpty {
            parts.append(
                valueNumberText + (unitText.isEmpty
                    ? "" : " " + unitText)
            )
        } else if !valueText.isEmpty {
            parts.append(valueText)
        }
        if deviates {
            parts.append(
                String(localized: "deviates")
            )
        }
        return parts.joined(separator: " · ")
    }

    public var asModel: ObservedSetting {
        get throws {
            try ObservedSetting(
                parameter: parameter,
                customParameter:
                    customParameter.isEmpty
                        ? nil : customParameter,
                scope: scope.isEmpty ? nil : scope,
                state: state,
                valueNumber: Double(valueNumberText),
                valueText:
                    valueText.isEmpty ? nil : valueText,
                unitText:
                    unitText.isEmpty ? nil : unitText,
                expectedNumber: Double(expectedNumberText),
                expectedText:
                    expectedText.isEmpty ? nil : expectedText,
                expectedUnitText:
                    expectedUnitText.isEmpty
                        ? nil : expectedUnitText,
                expectedSourceRef:
                    expectedSourceRef.isEmpty
                        ? nil : expectedSourceRef,
                deviatesFromExpected: deviates,
                deviationReason:
                    deviationReason.isEmpty
                        ? nil : deviationReason,
                evidenceRefs: evidenceRefs
            )
        }
    }
}

struct ObservedSettingFormView: View {
    @Binding var draft: ObservedSettingDraft
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?
    @State private var evidenceRefText = ""

    var body: some View {
        Form {
            Section(String(localized: "Setting")) {
                Picker(
                    String(localized: "Parameter"),
                    selection: $draft.parameter
                ) {
                    ForEach(
                        ObservedSettingParameter.allCases,
                        id: \.self
                    ) { parameter in
                        Text(
                            FieldAuthorityPresentation
                                .settingParameterName(
                                    parameter
                                )
                        )
                        .tag(parameter)
                    }
                }
                if draft.parameter == .other {
                    TextField(
                        String(localized:
                            "Parameter token (lowercase)"),
                        text: $draft.customParameter
                    )
                    .noAutocapitalization()
                }
                TextField(
                    String(localized:
                        "Scope (optional, e.g. channel:L)"),
                    text: $draft.scope
                )
                .noAutocapitalization()
                Picker(
                    String(localized: "State"),
                    selection: $draft.state
                ) {
                    ForEach(
                        [
                            ObservedSettingState.observed,
                            .unknown,
                            .notApplicable,
                        ],
                        id: \.self
                    ) { state in
                        Text(
                            FieldAuthorityPresentation
                                .settingStateName(state)
                        )
                        .tag(state)
                    }
                }
            }

            if draft.state == .observed {
                Section(String(localized: "Observed value")) {
                    TextField(
                        String(localized:
                            "Numeric value (optional)"),
                        text: $draft.valueNumberText
                    )
                    .decimalKeyboard()
                    TextField(
                        String(localized:
                            "Text value (optional)"),
                        text: $draft.valueText
                    )
                    TextField(
                        String(localized:
                            "Unit (optional, e.g. dB)"),
                        text: $draft.unitText
                    )
                    .noAutocapitalization()
                }
            }

            Section(
                String(localized:
                    "Expected value (optional)")
            ) {
                TextField(
                    String(localized:
                        "Expected numeric (optional)"),
                    text: $draft.expectedNumberText
                )
                .decimalKeyboard()
                TextField(
                    String(localized:
                        "Expected text (optional)"),
                    text: $draft.expectedText
                )
                TextField(
                    String(localized:
                        "Expected unit (optional)"),
                    text: $draft.expectedUnitText
                )
                .noAutocapitalization()
                TextField(
                    String(localized:
                        "Expected source ref (optional)"),
                    text: $draft.expectedSourceRef
                )
                .noAutocapitalization()
                Toggle(
                    String(localized: "Deviates from expected"),
                    isOn: $draft.deviates
                )
                if draft.deviates {
                    TextField(
                        String(localized:
                            "Deviation reason"),
                        text: $draft.deviationReason
                    )
                }
            }

            Section(String(localized: "Evidence refs")) {
                ForEach(draft.evidenceRefs, id: \.self) { ref in
                    Text(ref).font(.caption.monospaced())
                }
                .onDelete {
                    draft.evidenceRefs.remove(atOffsets: $0)
                }
                HStack {
                    TextField(
                        String(localized: "Add ref"),
                        text: $evidenceRefText
                    )
                    .noAutocapitalization()
                    Button(String(localized: "Add")) {
                        let ref = evidenceRefText
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        if !ref.isEmpty,
                           !draft.evidenceRefs.contains(ref)
                        {
                            draft.evidenceRefs.append(ref)
                            evidenceRefText = ""
                        }
                    }
                    .disabled(evidenceRefText.isEmpty)
                }
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(String(localized: "Observed setting"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Add")) {
                    do {
                        _ = try draft.asModel
                        onDone()
                        dismiss()
                    } catch {
                        errorText =
                            AnnotationPresentation
                                .errorText(error)
                    }
                }
            }
        }
    }
}

/// As-built wiring route form (issue #324): two exact termination
/// endpoints plus an ordered observed/estimated/hidden-unknown
/// segment path. Endpoints may be bound to a committed authority,
/// captured at the reticle, or labeled as a user-defined point; the
/// connector label names the physical port, never the entity center.
public struct WiringRouteFormView: View {
    public let captureRevisionID: CaptureRevisionID
    public let annotations: [CaptureAnnotationEntity]
    public let inventoryItems: [SystemInventoryItem]
    public let evidenceRefSuggestions: [String]
    public let selectedOperatorID: OperatorProfileID?
    /// Captures a world-space point under the reticle.
    public let captureTargetedPlacement:
        (PlacementTargetPreference) async throws
            -> AnnotationPlacementAuthority?
    public let onCommit: (AsBuiltWiringRoute) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var cableType = "speaker_wire"
    @State private var serviceType = ""
    @State private var state = WiringRouteState.observedAsBuilt
    @State private var endpointA = WiringTerminationDraft()
    @State private var endpointB = WiringTerminationDraft(
        kind: .avReceiver
    )
    @State private var segments: [WiringSegmentDraft] = []
    @State private var observedLengthText = ""
    @State private var estimatedLengthText = ""
    @State private var serviceLoopLengthText = ""
    @State private var evidenceRefs: [String] = []
    @State private var evidenceRefText = ""
    @State private var notes = ""
    @State private var errorText: String?

    public init(
        captureRevisionID: CaptureRevisionID,
        annotations: [CaptureAnnotationEntity] = [],
        inventoryItems: [SystemInventoryItem] = [],
        evidenceRefSuggestions: [String] = [],
        selectedOperatorID: OperatorProfileID? = nil,
        captureTargetedPlacement: @escaping
            (PlacementTargetPreference) async throws
            -> AnnotationPlacementAuthority? = { _ in nil },
        onCommit: @escaping (AsBuiltWiringRoute) -> Void
    ) {
        self.captureRevisionID = captureRevisionID
        self.annotations = annotations
        self.inventoryItems = inventoryItems
        self.evidenceRefSuggestions = evidenceRefSuggestions
        self.selectedOperatorID = selectedOperatorID
        self.captureTargetedPlacement =
            captureTargetedPlacement
        self.onCommit = onCommit
    }

    private var bindingOptions:
        [(ref: String, label: String)]
    {
        var options: [(String, String)] = []
        for item in inventoryItems {
            options.append((
                "inventory_item:" + item.itemID.description,
                item.userLabel
            ))
        }
        for entity in annotations {
            options.append((
                "entity:" + entity.entityID.description,
                entity.label
            ))
        }
        return options
    }

    public var body: some View {
        Form {
            Section(String(localized: "Cable")) {
                TextField(
                    String(localized: "Cable type"),
                    text: $cableType
                )
                .noAutocapitalization()
                TextField(
                    String(localized:
                        "Service type (optional, e.g. front_l)"),
                    text: $serviceType
                )
                .noAutocapitalization()
                Picker(
                    String(localized: "Record state"),
                    selection: $state
                ) {
                    ForEach(
                        WiringRouteState.allCases,
                        id: \.self
                    ) { value in
                        Text(
                            FieldAuthorityPresentation
                                .routeStateName(value)
                        )
                        .tag(value)
                    }
                }
            }

            endpointSection(
                title: String(localized: "Endpoint A"),
                draft: $endpointA
            )
            endpointSection(
                title: String(localized: "Endpoint B"),
                draft: $endpointB
            )

            Section(
                String(localized: "Cable path")
            ) {
                if segments.isEmpty {
                    Text(
                        String(localized:
                            "No path segments recorded.")
                    )
                    .foregroundStyle(.secondary)
                }
                ForEach($segments) { $segment in
                    SegmentEditor(
                        segment: $segment,
                        onDelete: {
                            segments.removeAll {
                                $0.id == segment.id
                            }
                            renumber()
                        }
                    ) {
                        try await capturePoint()
                    }
                }
                Button(
                    String(localized: "Add path segment")
                ) {
                    segments.append(
                        WiringSegmentDraft(
                            order: segments.count
                        )
                    )
                }
                Text(
                    "Mark concealed sections as Hidden (unknown) — they carry no geometry so an unobserved in-wall run is never guessed."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(String(localized: "Lengths (m)")) {
                TextField(
                    String(localized:
                        "Measured length (optional)"),
                    text: $observedLengthText
                )
                .decimalKeyboard()
                TextField(
                    String(localized:
                        "Estimated length (optional)"),
                    text: $estimatedLengthText
                )
                .decimalKeyboard()
                TextField(
                    String(localized:
                        "Service loop / slack (optional)"),
                    text: $serviceLoopLengthText
                )
                .decimalKeyboard()
            }

            Section(String(localized: "Evidence refs")) {
                ForEach(evidenceRefs, id: \.self) { ref in
                    Text(ref).font(.caption.monospaced())
                }
                .onDelete {
                    evidenceRefs.remove(atOffsets: $0)
                }
                ForEach(
                    evidenceRefSuggestions,
                    id: \.self
                ) { suggestion in
                    if !evidenceRefs.contains(suggestion) {
                        Button(suggestion) {
                            evidenceRefs.append(suggestion)
                        }
                        .font(.caption.monospaced())
                    }
                }
                HStack {
                    TextField(
                        String(localized: "Add ref"),
                        text: $evidenceRefText
                    )
                    .noAutocapitalization()
                    Button(String(localized: "Add")) {
                        let ref = evidenceRefText
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        if !ref.isEmpty,
                           !evidenceRefs.contains(ref)
                        {
                            evidenceRefs.append(ref)
                            evidenceRefText = ""
                        }
                    }
                    .disabled(evidenceRefText.isEmpty)
                }
            }

            Section(String(localized: "Notes")) {
                TextField(
                    String(localized: "Notes (optional)"),
                    text: $notes,
                    axis: .vertical
                )
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(
            String(localized: "Record wiring route")
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Save")) { save() }
            }
        }
    }

    @ViewBuilder
    private func endpointSection(
        title: String,
        draft: Binding<WiringTerminationDraft>
    ) -> some View {
        Section(title) {
            Picker(
                String(localized: "Endpoint kind"),
                selection: draft.kind
            ) {
                ForEach(
                    WiringTerminationKind.allCases,
                    id: \.self
                ) { kind in
                    Text(
                        FieldAuthorityPresentation
                            .terminationKindName(kind)
                    )
                    .tag(kind)
                }
            }
            TextField(
                String(localized: "Label (optional)"),
                text: draft.label
            )
            Picker(
                String(localized: "Bound authority (optional)"),
                selection: draft.bindingRef
            ) {
                Text(String(localized: "None")).tag("")
                ForEach(bindingOptions, id: \.ref) { option in
                    Text(option.label).tag(option.ref)
                }
            }
            TextField(
                String(localized:
                    "Connector / port (optional)"),
                text: draft.connectorLabel
            )
            if let position = draft.wrappedValue.position {
                Text(
                    String(
                        format:
                            "Captured point: (%.2f, %.2f, %.2f)",
                        position.point.x,
                        position.point.y,
                        position.point.z
                    )
                )
                .font(.caption.monospaced())
            }
            Button(
                String(localized:
                    "Capture endpoint position")
            ) {
                Task { @MainActor in
                    do {
                        let point =
                            try await capturePoint()
                        draft.wrappedValue.position = point
                    } catch {
                        errorText =
                            AnnotationPresentation
                                .errorText(error)
                    }
                }
            }
        }
    }

    /// Captures the world-space point under the reticle via the
    /// shared targeted-placement capture.
    private func capturePoint() async throws
        -> (point: SpatialVector3F, space: CoordinateSpaceID)
    {
        guard let authority = try await captureTargetedPlacement(
            .automatic
        ) else {
            throw FieldAuthorityModelError.endpointConflict
        }
        let values = authority.worldFromAnnotation.values
        return (
            try SpatialVector3F(
                values[12], values[13], values[14]
            ),
            authority.coordinateSpaceID
        )
    }

    private func renumber() {
        for index in segments.indices {
            segments[index].order = index
        }
    }

    private func save() {
        do {
            let termA = try endpointA.asModel()
            let termB = try endpointB.asModel()
            let builtSegments = try segments.map {
                try $0.asModel()
            }
            let route = try AsBuiltWiringRoute(
                captureRevisionID: captureRevisionID,
                cableType: cableType,
                serviceType: serviceType.isEmpty
                    ? nil : serviceType,
                state: state,
                endpointA: termA,
                endpointB: termB,
                segments: builtSegments,
                observedLengthM: Double(observedLengthText),
                estimatedLengthM: Double(estimatedLengthText),
                serviceLoopLengthM: Double(serviceLoopLengthText),
                evidenceRefs: evidenceRefs,
                notes: notes.isEmpty ? nil : notes,
                operatorID: selectedOperatorID
            )
            onCommit(route)
            dismiss()
        } catch {
            errorText =
                AnnotationPresentation.errorText(error)
        }
    }
}

/// Editable endpoint draft (issue #324).
public struct WiringTerminationDraft: Sendable {
    public var kind: WiringTerminationKind
    public var label = ""
    public var bindingRef = ""
    public var connectorLabel = ""
    public var position:
        (point: SpatialVector3F, space: CoordinateSpaceID)?

    public init(
        kind: WiringTerminationKind = .speaker
    ) {
        self.kind = kind
    }

    func asModel() throws -> WiringTermination {
        try WiringTermination(
            kind: kind,
            label: label.isEmpty ? nil : label,
            bindingRef: bindingRef.isEmpty ? nil : bindingRef,
            connectorLabel: connectorLabel.isEmpty
                ? nil : connectorLabel,
            coordinateSpaceID: position?.space,
            worldFromEndpoint: position.map {
                try! Matrix4x4F(values: [
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    $0.point.x, $0.point.y, $0.point.z, 1,
                ])
            }
        )
    }
}

/// Editable path-segment draft (issue #324).
public struct WiringSegmentDraft: Identifiable, Sendable {
    public let id = UUID()
    public var order: Int
    public var observation:
        WiringSegmentObservation = .observed
    public var waypoints: [SpatialVector3F] = []
    public var surfaceRef = ""
    public var evidenceRefs: [String] = []

    public init(order: Int) {
        self.order = order
    }

    func asModel() throws -> WiringSegment {
        try WiringSegment(
            order: order,
            observation: observation,
            waypoints: observation == .hiddenUnknown
                ? [] : waypoints,
            surfaceRef: surfaceRef.isEmpty ? nil : surfaceRef,
            evidenceRefs: evidenceRefs
        )
    }
}

struct SegmentEditor: View {
    @Binding var segment: WiringSegmentDraft
    let onDelete: () -> Void
    let capturePoint: () async throws
        -> (point: SpatialVector3F, space: CoordinateSpaceID)
    @State private var waypointText = ""
    @State private var capturing = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(segment.order)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "minus.circle")
                }
            }
            Picker(
                String(localized: "Observation"),
                selection: $segment.observation
            ) {
                ForEach(
                    [
                        WiringSegmentObservation.observed,
                        .estimated,
                        .hiddenUnknown,
                    ],
                    id: \.self
                ) { observation in
                    Text(
                        FieldAuthorityPresentation
                            .segmentObservationName(
                                observation
                            )
                    )
                    .tag(observation)
                }
            }
            if segment.observation != .hiddenUnknown {
                ForEach(
                    Array(segment.waypoints.enumerated()),
                    id: \.offset
                ) { index, point in
                    HStack {
                        Text(
                            String(
                                format:
                                    "(%.2f, %.2f, %.2f)",
                                point.x, point.y, point.z
                            )
                        )
                        .font(.caption.monospaced())
                        Spacer()
                        Button(role: .destructive) {
                            segment.waypoints.remove(
                                at: index
                            )
                        } label: {
                            Image(
                                systemName:
                                    "minus.circle"
                            )
                        }
                    }
                }
                HStack {
                    TextField(
                        String(localized:
                            "x,y,z (optional manual point)"),
                        text: $waypointText
                    )
                    .noAutocapitalization()
                    Button(String(localized: "Add")) {
                        addManualWaypoint()
                    }
                    .disabled(waypointText.isEmpty)
                }
                Button(
                    capturing
                        ? String(localized: "Capturing…")
                        : String(localized:
                            "Capture waypoint at reticle")
                ) {
                    capturing = true
                    Task { @MainActor in
                        do {
                            let point =
                                try await capturePoint()
                            segment.waypoints.append(
                                point.point
                            )
                        } catch {
                            errorText =
                                AnnotationPresentation
                                    .errorText(error)
                        }
                        capturing = false
                    }
                }
                .disabled(capturing)
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
    }

    private func addManualWaypoint() {
        let parts = waypointText.split(separator: ",")
            .map {
                $0.trimmingCharacters(
                    in: .whitespaces
                )
            }
            .compactMap(Float.init)
        guard parts.count == 3,
              let point = try? SpatialVector3F(
                  parts[0], parts[1], parts[2]
              )
        else {
            errorText = String(
                localized:
                    "Enter x,y,z numeric coordinates"
            )
            return
        }
        segment.waypoints.append(point)
        waypointText = ""
        errorText = nil
    }
}

private extension View {
    /// Lowercase-token fields should never be autocapitalized; no-op on
    /// macOS where `autocapitalization` is unavailable.
    @ViewBuilder func noAutocapitalization() -> some View {
        #if os(iOS)
        autocapitalization(.none)
        #else
        self
        #endif
    }
}

extension MeasurementInstrumentProfile: Identifiable {
    public var id: String {
        instrumentID.description + ":" + String(profileVersion)
    }
}
