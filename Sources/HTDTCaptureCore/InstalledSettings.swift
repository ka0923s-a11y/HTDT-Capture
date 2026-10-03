import Foundation

public struct SettingsObservationID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Enumerated setting-parameter tokens recorded by an installed
/// settings observation (issue bolph71656-ai/HTDT-Capture#301). Covers the commissioning field
/// set — per-channel gain/delay/crossover/polarity, speaker size and
/// bass management, PEQ band parameters, DSP/processor presets and
/// modes, and physical subwoofer knobs — plus `other` for anything the
/// enumeration does not yet name (then `custom_parameter` is required).
public enum ObservedSettingParameter: String, Codable, Sendable,
    CaseIterable
{
    case channelGain = "channel_gain"
    case channelDelay = "channel_delay"
    case channelDistance = "channel_distance"
    case crossoverFrequency = "crossover_frequency"
    case polarity
    case speakerSize = "speaker_size"
    case bassManagement = "bass_management"
    case peqBandFrequency = "peq_band_frequency"
    case peqBandGain = "peq_band_gain"
    case peqBandQ = "peq_band_q"
    case peqEnabled = "peq_enabled"
    case dspPreset = "dsp_preset"
    case dspMode = "dsp_mode"
    case processorPreset = "processor_preset"
    case processorMode = "processor_mode"
    case subwooferGain = "subwoofer_gain"
    case subwooferPhase = "subwoofer_phase"
    case subwooferCrossover = "subwoofer_crossover"
    case subwooferPolarity = "subwoofer_polarity"
    case other
}

/// Tri-state for an observed setting (issue bolph71656-ai/HTDT-Capture#301): a physically read
/// value, an explicit `unknown` (checked but not determinable), or an
/// explicit `not_applicable`. Never silently absent.
public enum ObservedSettingState: String, Codable, Sendable {
    case observed
    case unknown
    case notApplicable = "not_applicable"
}

/// One observed setting inside an installed-settings observation
/// (issue bolph71656-ai/HTDT-Capture#301). `scope` binds the setting to a channel/PQ band/subwoofer
/// within the target device — a lowercase namespace token plus id
/// (`channel:L`, `peq_band:3`, `sub:SW1`) or the literal `global`.
///
/// `value_number`/`value_text` hold the effective setting read from the
/// device; `expected_number`/`expected_text`/`expected_unit_text` carry
/// the plan's expected value when one was supplied. A setting recorded
/// as deviating must say why (`deviation_reason`) or carry evidence.
public struct ObservedSetting: Codable, Sendable, Equatable {
    public let parameter: ObservedSettingParameter
    /// Required iff `parameter == .other`; a `[a-z0-9_]+` token.
    public let customParameter: String?
    /// `global` or `namespace:id` token; nil means the whole device.
    public let scope: String?
    public let state: ObservedSettingState
    public let valueNumber: Double?
    public let valueText: String?
    /// Short unit token ("dB", "Hz", "ms") when numeric.
    public let unitText: String?
    public let expectedNumber: Double?
    public let expectedText: String?
    public let expectedUnitText: String?
    /// Exact binding ref of the plan item the expected value came
    /// from (e.g. `calibration_plan_item:<id>`), when the expected
    /// value is plan-sourced.
    public let expectedSourceRef: String?
    public let deviatesFromExpected: Bool
    public let deviationReason: String?
    public let evidenceRefs: [String]

    public init(
        parameter: ObservedSettingParameter,
        customParameter: String? = nil,
        scope: String? = nil,
        state: ObservedSettingState,
        valueNumber: Double? = nil,
        valueText: String? = nil,
        unitText: String? = nil,
        expectedNumber: Double? = nil,
        expectedText: String? = nil,
        expectedUnitText: String? = nil,
        expectedSourceRef: String? = nil,
        deviatesFromExpected: Bool = false,
        deviationReason: String? = nil,
        evidenceRefs: [String] = []
    ) throws {
        let normalizedCustom = SchemaOwnedText.nfc(customParameter)
        if parameter == .other {
            guard let custom = normalizedCustom,
                  FieldAuthorityGrammar.isLowercaseToken(custom)
            else {
                throw FieldAuthorityModelError
                    .invalidToken("custom_parameter")
            }
        } else if normalizedCustom != nil {
            throw FieldAuthorityModelError
                .invalidToken("custom_parameter")
        }
        let normalizedScope = SchemaOwnedText.nfc(scope)
        if let scope = normalizedScope {
            guard Self.isScopeToken(scope) else {
                throw FieldAuthorityModelError.invalidToken(scope)
            }
        }
        switch state {
        case .observed:
            guard valueNumber != nil
                    || (valueText?.isEmpty == false)
            else {
                throw FieldAuthorityModelError.invalidObservedValue
            }
        case .unknown, .notApplicable:
            guard valueNumber == nil, valueText == nil,
                  unitText == nil
            else {
                throw FieldAuthorityModelError.invalidObservedValue
            }
        }
        if let valueNumber {
            guard valueNumber.isFinite else {
                throw FieldAuthorityModelError.invalidObservedValue
            }
        }
        if let expectedNumber {
            guard expectedNumber.isFinite else {
                throw FieldAuthorityModelError.invalidObservedValue
            }
        }
        let normalizedExpectedRef = SchemaOwnedText
            .nfc(expectedSourceRef)
        if let expectedRef = normalizedExpectedRef {
            guard FieldAuthorityGrammar.isBindingRef(expectedRef)
            else {
                throw FieldAuthorityModelError
                    .unboundReference(expectedRef)
            }
        }
        let normalizedDeviation = SchemaOwnedText.nfc(deviationReason)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if deviatesFromExpected {
            guard (normalizedDeviation?.isEmpty == false)
                    || !evidenceRefs.isEmpty
            else {
                throw FieldAuthorityModelError
                    .attestationRequired
            }
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy(
            FieldAuthorityGrammar.isEvidenceRef
        ) else {
            throw FieldAuthorityModelError
                .unboundReference("evidence_refs")
        }

        self.parameter = parameter
        self.customParameter = normalizedCustom
        self.scope = normalizedScope
        self.state = state
        self.valueNumber = valueNumber
        self.valueText = SchemaOwnedText.nfc(valueText)
        self.unitText = SchemaOwnedText.nfc(unitText)
        self.expectedNumber = expectedNumber
        self.expectedText = SchemaOwnedText.nfc(expectedText)
        self.expectedUnitText = SchemaOwnedText.nfc(expectedUnitText)
        self.expectedSourceRef = normalizedExpectedRef
        self.deviatesFromExpected = deviatesFromExpected
        self.deviationReason = normalizedDeviation
        self.evidenceRefs = normalizedEvidence.sorted()
    }

    static func isScopeToken(_ value: String) -> Bool {
        if value == "global" {
            return true
        }
        guard let colon = value.firstIndex(of: ":") else {
            return false
        }
        let namespace = String(value[..<colon])
        let identifier = String(value[value.index(after: colon)...])
        guard FieldAuthorityGrammar.isLowercaseToken(namespace),
              !identifier.isEmpty,
              identifier.unicodeScalars.allSatisfy({
                  $0.value >= 0x21 && $0.value <= 0x7E
              })
        else {
            return false
        }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case parameter
        case customParameter = "custom_parameter"
        case scope
        case state
        case valueNumber = "value_number"
        case valueText = "value_text"
        case unitText = "unit_text"
        case expectedNumber = "expected_number"
        case expectedText = "expected_text"
        case expectedUnitText = "expected_unit_text"
        case expectedSourceRef = "expected_source_ref"
        case deviatesFromExpected = "deviates_from_expected"
        case deviationReason = "deviation_reason"
        case evidenceRefs = "evidence_refs"
    }
}

/// One commissioning observation of an installed device's effective
/// settings (issue bolph71656-ai/HTDT-Capture#301): the operator's field record of an AVR, DSP,
/// processor or subwoofer — bound to the exact device authority via
/// `target_ref` (`inventory_item:`/`entity:`/`equipment:`), with its
/// own timestamp and optional operator identity. Observations are user
/// attestation only: they never mutate a `CalibrationPlan` and never
/// become equipment truth.
public struct InstalledSettingsObservation: Codable, Sendable,
    Equatable
{
    public let observationID: SettingsObservationID
    public let captureRevisionID: CaptureRevisionID
    public let targetRef: String
    public let recordedAtUTC: String
    public let operatorID: OperatorProfileID?
    public let settings: [ObservedSetting]
    public let evidenceRefs: [String]
    public let notes: String?

    public init(
        observationID: SettingsObservationID = SettingsObservationID(),
        captureRevisionID: CaptureRevisionID,
        targetRef: String,
        recordedAtUTC: String = BundleTimestamp.utcString(from: Date()),
        operatorID: OperatorProfileID? = nil,
        settings: [ObservedSetting],
        evidenceRefs: [String] = [],
        notes: String? = nil
    ) throws {
        guard FieldAuthorityGrammar.isBindingRef(targetRef) else {
            throw FieldAuthorityModelError.unboundReference(targetRef)
        }
        guard !settings.isEmpty else {
            throw FieldAuthorityModelError.emptyField("settings")
        }
        guard SchemaTimestampText.isUTCTimestamp(recordedAtUTC) else {
            throw FieldAuthorityModelError
                .invalidTimestamp(recordedAtUTC)
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy(
            FieldAuthorityGrammar.isEvidenceRef
        ) else {
            throw FieldAuthorityModelError
                .unboundReference("evidence_refs")
        }
        self.observationID = observationID
        self.captureRevisionID = captureRevisionID
        self.targetRef = targetRef
        self.recordedAtUTC = recordedAtUTC
        self.operatorID = operatorID
        self.settings = settings
        self.evidenceRefs = normalizedEvidence.sorted()
        self.notes = SchemaOwnedText.nfc(notes)
    }

    private enum CodingKeys: String, CodingKey {
        case observationID = "observation_id"
        case captureRevisionID = "capture_revision_id"
        case targetRef = "target_ref"
        case recordedAtUTC = "recorded_at_utc"
        case operatorID = "operator_id"
        case settings
        case evidenceRefs = "evidence_refs"
        case notes
    }
}

/// The derived `derived/settings-observations.json` payload (issue
/// legacy bolph71656-ai/HTDT-Capture#301): committed installed-settings observations for the revision.
public struct InstalledSettingsDocument: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.settings-observations"
    public static let schemaVersion = "1.0.0"

    public let schemaName: String
    public let schemaVersionValue: String
    public let captureRevisionID: CaptureRevisionID
    public let recordedAtUTC: String
    public let observations: [InstalledSettingsObservation]

    public init(
        captureRevisionID: CaptureRevisionID,
        observations: [InstalledSettingsObservation],
        recordedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws {
        let ids = observations.map(\.observationID)
        guard Set(ids).count == ids.count else {
            throw FieldAuthorityModelError
                .duplicateRecord("observation_id")
        }
        guard observations.allSatisfy({
            $0.captureRevisionID == captureRevisionID
        }) else {
            throw FieldAuthorityModelError
                .unboundReference("capture_revision_id")
        }
        guard SchemaTimestampText.isUTCTimestamp(recordedAtUTC) else {
            throw FieldAuthorityModelError
                .invalidTimestamp(recordedAtUTC)
        }
        self.schemaName = Self.schema
        self.schemaVersionValue = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.recordedAtUTC = recordedAtUTC
        self.observations = observations
    }

    private enum CodingKeys: String, CodingKey {
        case schemaName = "schema"
        case schemaVersionValue = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case recordedAtUTC = "recorded_at_utc"
        case observations
    }
}

/// Encoded `InstalledSettingsDocument` ready for the working-set store.
public struct InstalledSettingsPackage: Sendable, Equatable {
    public static let path = "derived/settings-observations.json"
    public static let sourceRef = "path:" + path

    public let document: InstalledSettingsDocument
    public let data: Data
    public let sourceRefs: [String]

    public init(document: InstalledSettingsDocument) throws {
        var refs = Set<String>()
        for observation in document.observations {
            if observation.targetRef.hasPrefix("entity:") {
                refs.insert("path:" + AnnotationEvidencePackage.path)
            } else if observation.targetRef
                .hasPrefix("inventory_item:")
            {
                refs.insert("path:" + TheaterAuthorityPackage.path)
            }
            for ref in observation.evidenceRefs
                + observation.settings.flatMap(\.evidenceRefs)
            where ref.hasPrefix("path:") || ref.hasPrefix("frame:")
            {
                if ref.hasPrefix("frame:") {
                    refs.insert(
                        "path:evidence/frames/"
                            + ref.dropFirst("frame:".count) + ".json"
                    )
                } else {
                    refs.insert(ref)
                }
            }
            if observation.operatorID != nil {
                refs.insert("path:" + OperatorProfilePackage.path)
            }
        }
        if refs.isEmpty {
            refs.insert("path:session/capture-session.json")
        }
        self.document = document
        self.sourceRefs = refs.sorted()
        self.data = try FieldAuthorityCoding.encoder()
            .encode(document)
    }
}
