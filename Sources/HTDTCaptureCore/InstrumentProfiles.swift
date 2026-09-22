import Foundation

public struct InstrumentProfileID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Broad instrument classes for `MeasurementInstrumentProfile`
/// (issue #331). Stable machine tokens — never display text.
public enum MeasurementInstrumentClass: String, Codable, Sendable,
    CaseIterable
{
    case tapeMeasure = "tape_measure"
    case laserDistanceMeter = "laser_distance_meter"
    case measurementMicrophone = "measurement_microphone"
    case splMeter = "spl_meter"
    case microphoneCalibrator = "microphone_calibrator"
    case audioAnalyzer = "audio_analyzer"
    case thermometer
    case hygrometer
    case levelInstrument = "level_instrument"
    case scale
    case other
}

/// Calibration state of an instrument profile (issue #331).
/// `unknown` is explicit — never a silently absent field.
public enum InstrumentCalibrationState: String, Codable, Sendable,
    CaseIterable
{
    case calibrated
    case uncalibrated
    case expired
    case notApplicable = "not_applicable"
    case unknown
}

/// The kind of artifact backing a calibration claim (issue #331):
/// an external certificate/document kept as immutable source evidence,
/// a microphone calibration file, a manufacturer record, or — at
/// weakest — a user attestation recorded as such.
public enum CalibrationEvidenceKind: String, Codable, Sendable,
    CaseIterable
{
    case calibrationCertificate = "calibration_certificate"
    case microphoneCalibrationFile = "microphone_calibration_file"
    case manufacturerRecord = "manufacturer_record"
    case userAttestation = "user_attestation"
    case other
}

/// Exact device authority for a measurement instrument (issue #331).
/// Replaces bare make/model text on a measurement: the profile names
/// the concrete instrument (class, manufacturer, model, optional
/// serial/asset id), its calibration state and exact calibration
/// evidence (`path:` bundle asset, `frame:`/scan frame,
/// `field_evidence:` record, or `sha256:` digest refs), and carries a
/// `profile_sha256` digest computed over every other field. Any field
/// change therefore mints a new immutable `profile_version`; committed
/// measurements keep naming the exact version/digest they used.
public struct MeasurementInstrumentProfile: Codable, Sendable,
    Equatable
{
    public let instrumentID: InstrumentProfileID
    /// 1-based immutable version of this instrument's profile fields.
    public let profileVersion: Int
    public let instrumentClass: MeasurementInstrumentClass
    public let manufacturer: String?
    public let model: String
    /// Optional serial/asset identifier — privacy-sensitive, surfaced
    /// in Review before export.
    public let serialOrAssetID: String?
    public let calibrationState: InstrumentCalibrationState
    public let calibrationDate: String?
    /// End of the calibration's validity window, when declared.
    public let calibrationValidUntil: String?
    /// What kind of artifact backs the calibration claim; required
    /// unless `calibration_state` is `unknown`/`not_applicable`.
    public let calibrationEvidenceKind: CalibrationEvidenceKind?
    /// Exact evidence refs for the calibration artifact.
    public let calibrationEvidenceRefs: [String]
    /// Operator-stated accuracy text (e.g. "±0.5 dB").
    public let statedAccuracy: String?
    /// Optional operator-friendly label ("lab mic", "workshop laser").
    public let operatorLabel: String?
    public let createdAtUTC: String
    /// SHA-256 of the canonical encoding of every other field — the
    /// digest measurements bind to via `instrument_authority`.
    public let profileSHA256: EvidenceSHA256

    public init(
        instrumentID: InstrumentProfileID = InstrumentProfileID(),
        profileVersion: Int = 1,
        instrumentClass: MeasurementInstrumentClass,
        manufacturer: String? = nil,
        model: String,
        serialOrAssetID: String? = nil,
        calibrationState: InstrumentCalibrationState = .unknown,
        calibrationDate: String? = nil,
        calibrationValidUntil: String? = nil,
        calibrationEvidenceKind: CalibrationEvidenceKind? = nil,
        calibrationEvidenceRefs: [String] = [],
        statedAccuracy: String? = nil,
        operatorLabel: String? = nil,
        createdAtUTC: String = BundleTimestamp.utcString(
            from: Date()
        )
    ) throws {
        guard profileVersion >= 1 else {
            throw FieldAuthorityModelError.unknownInstrumentVersion
        }
        let normalizedModel = SchemaOwnedText.nfc(model)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else {
            throw FieldAuthorityModelError.emptyField("model")
        }
        guard SchemaTimestampText.isUTCTimestamp(createdAtUTC) else {
            throw FieldAuthorityModelError
                .invalidTimestamp(createdAtUTC)
        }
        if let calibrationDate {
            guard SchemaTimestampText.isCalendarDate(calibrationDate)
            else {
                throw FieldAuthorityModelError
                    .invalidCalendarDate(calibrationDate)
            }
        }
        if let calibrationValidUntil {
            guard SchemaTimestampText.isCalendarDate(
                calibrationValidUntil
            ) else {
                throw FieldAuthorityModelError
                    .invalidCalendarDate(calibrationValidUntil)
            }
        }
        if let calibrationDate, let calibrationValidUntil,
           calibrationValidUntil < calibrationDate
        {
            throw FieldAuthorityModelError.invalidCalibrationWindow
        }
        switch calibrationState {
        case .calibrated:
            guard calibrationDate != nil else {
                throw FieldAuthorityModelError
                    .invalidCalibrationWindow
            }
        case .uncalibrated, .expired:
            break
        case .unknown, .notApplicable:
            guard calibrationEvidenceKind == nil,
                  calibrationEvidenceRefs.isEmpty
            else {
                throw FieldAuthorityModelError
                    .invalidCalibrationWindow
            }
        }
        if calibrationEvidenceKind != nil,
           calibrationEvidenceRefs.isEmpty
        {
            // A named evidence kind without any reference carries no
            // authority either.
            throw FieldAuthorityModelError.unboundReference(
                "calibration_evidence_refs"
            )
        }
        let normalizedEvidence = SchemaOwnedText
            .nfc(calibrationEvidenceRefs)
        guard normalizedEvidence.allSatisfy(
            FieldAuthorityGrammar.isEvidenceRef
        ), Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw FieldAuthorityModelError.unboundReference(
                "calibration_evidence_refs"
            )
        }

        self.instrumentID = instrumentID
        self.profileVersion = profileVersion
        self.instrumentClass = instrumentClass
        self.manufacturer = SchemaOwnedText.nfc(manufacturer)
        self.model = normalizedModel
        self.serialOrAssetID = SchemaOwnedText.nfc(serialOrAssetID)
        self.calibrationState = calibrationState
        self.calibrationDate = calibrationDate
        self.calibrationValidUntil = calibrationValidUntil
        self.calibrationEvidenceKind = calibrationEvidenceKind
        self.calibrationEvidenceRefs = normalizedEvidence.sorted()
        self.statedAccuracy = SchemaOwnedText.nfc(statedAccuracy)
        self.operatorLabel = SchemaOwnedText.nfc(operatorLabel)
        self.createdAtUTC = createdAtUTC
        self.profileSHA256 = try Self.computeDigest(
            instrumentID: instrumentID,
            profileVersion: profileVersion,
            instrumentClass: instrumentClass,
            manufacturer: manufacturer,
            model: normalizedModel,
            serialOrAssetID: serialOrAssetID,
            calibrationState: calibrationState,
            calibrationDate: calibrationDate,
            calibrationValidUntil: calibrationValidUntil,
            calibrationEvidenceKind: calibrationEvidenceKind,
            calibrationEvidenceRefs: normalizedEvidence.sorted(),
            statedAccuracy: statedAccuracy,
            operatorLabel: operatorLabel,
            createdAtUTC: createdAtUTC
        )
    }

    /// The digest commits to the raw text the operator typed (not the
    /// NFC-normalized copies) only insofar as the stored fields do —
    /// it hashes exactly what is persisted, so both sides of a bind
    /// compare equal.
    private static func computeDigest(
        instrumentID: InstrumentProfileID,
        profileVersion: Int,
        instrumentClass: MeasurementInstrumentClass,
        manufacturer: String?,
        model: String,
        serialOrAssetID: String?,
        calibrationState: InstrumentCalibrationState,
        calibrationDate: String?,
        calibrationValidUntil: String?,
        calibrationEvidenceKind: CalibrationEvidenceKind?,
        calibrationEvidenceRefs: [String],
        statedAccuracy: String?,
        operatorLabel: String?,
        createdAtUTC: String
    ) throws -> EvidenceSHA256 {
        let content = DigestContent(
            instrumentID: instrumentID,
            profileVersion: profileVersion,
            instrumentClass: instrumentClass,
            manufacturer: SchemaOwnedText.nfc(manufacturer),
            model: model,
            serialOrAssetID: SchemaOwnedText.nfc(serialOrAssetID),
            calibrationState: calibrationState,
            calibrationDate: calibrationDate,
            calibrationValidUntil: calibrationValidUntil,
            calibrationEvidenceKind: calibrationEvidenceKind,
            calibrationEvidenceRefs: calibrationEvidenceRefs,
            statedAccuracy: SchemaOwnedText.nfc(statedAccuracy),
            operatorLabel: SchemaOwnedText.nfc(operatorLabel),
            createdAtUTC: createdAtUTC
        )
        let data = try FieldAuthorityCoding.encoder().encode(content)
        return EvidenceIntegrity.sha256(of: data)
    }

    /// Recomputes the digest over the decoded fields; used by the
    /// document to verify a persisted profile was not edited under its
    /// frozen digest.
    public func verifyDigest() -> Bool {
        (try? Self.computeDigest(
            instrumentID: instrumentID,
            profileVersion: profileVersion,
            instrumentClass: instrumentClass,
            manufacturer: manufacturer,
            model: model,
            serialOrAssetID: serialOrAssetID,
            calibrationState: calibrationState,
            calibrationDate: calibrationDate,
            calibrationValidUntil: calibrationValidUntil,
            calibrationEvidenceKind: calibrationEvidenceKind,
            calibrationEvidenceRefs: calibrationEvidenceRefs,
            statedAccuracy: statedAccuracy,
            operatorLabel: operatorLabel,
            createdAtUTC: createdAtUTC
        )) == profileSHA256
    }

    /// The exact identity triple a measurement binds to. Safe to
    /// force-try: `profileVersion >= 1` was validated at init.
    public var reference: MeasurementInstrumentReference {
        try! MeasurementInstrumentReference(
            instrumentID: instrumentID,
            profileVersion: profileVersion,
            profileSHA256: profileSHA256
        )
    }

    private struct DigestContent: Codable {
        let instrumentID: InstrumentProfileID
        let profileVersion: Int
        let instrumentClass: MeasurementInstrumentClass
        let manufacturer: String?
        let model: String
        let serialOrAssetID: String?
        let calibrationState: InstrumentCalibrationState
        let calibrationDate: String?
        let calibrationValidUntil: String?
        let calibrationEvidenceKind: CalibrationEvidenceKind?
        let calibrationEvidenceRefs: [String]
        let statedAccuracy: String?
        let operatorLabel: String?
        let createdAtUTC: String

        enum CodingKeys: String, CodingKey {
            case instrumentID = "instrument_id"
            case profileVersion = "profile_version"
            case instrumentClass = "instrument_class"
            case manufacturer
            case model
            case serialOrAssetID = "serial_or_asset_id"
            case calibrationState = "calibration_state"
            case calibrationDate = "calibration_date"
            case calibrationValidUntil = "calibration_valid_until"
            case calibrationEvidenceKind = "calibration_evidence_kind"
            case calibrationEvidenceRefs = "calibration_evidence_refs"
            case statedAccuracy = "stated_accuracy"
            case operatorLabel = "operator_label"
            case createdAtUTC = "created_at_utc"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case instrumentID = "instrument_id"
        case profileVersion = "profile_version"
        case instrumentClass = "instrument_class"
        case manufacturer
        case model
        case serialOrAssetID = "serial_or_asset_id"
        case calibrationState = "calibration_state"
        case calibrationDate = "calibration_date"
        case calibrationValidUntil = "calibration_valid_until"
        case calibrationEvidenceKind = "calibration_evidence_kind"
        case calibrationEvidenceRefs = "calibration_evidence_refs"
        case statedAccuracy = "stated_accuracy"
        case operatorLabel = "operator_label"
        case createdAtUTC = "created_at_utc"
        case profileSHA256 = "profile_sha256"
    }
}

/// The `(instrument_id, profile_version, profile_sha256)` triple a
/// `CaptureMeasurement` binds to the exact instrument profile version
/// it relied on (issue #331).
public struct MeasurementInstrumentReference: Codable, Sendable,
    Equatable, Hashable
{
    public let instrumentID: InstrumentProfileID
    public let profileVersion: Int
    public let profileSHA256: EvidenceSHA256

    public init(
        instrumentID: InstrumentProfileID,
        profileVersion: Int,
        profileSHA256: EvidenceSHA256
    ) throws {
        guard profileVersion >= 1 else {
            throw FieldAuthorityModelError.unknownInstrumentVersion
        }
        self.instrumentID = instrumentID
        self.profileVersion = profileVersion
        self.profileSHA256 = profileSHA256
    }

    private enum CodingKeys: String, CodingKey {
        case instrumentID = "instrument_id"
        case profileVersion = "profile_version"
        case profileSHA256 = "profile_sha256"
    }
}

/// The derived `derived/instrument-profiles.json` registry (issue
/// #331): every instrument profile version ever committed for the
/// revision. `(instrument_id, profile_version)` pairs are unique and a
/// stored digest must still match its fields — a silently edited
/// profile fails validation instead of changing meaning under the
/// measurements that bound it.
public struct InstrumentProfileDocument: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.instrument-profiles"
    public static let schemaVersion = "1.0.0"

    public let schemaName: String
    public let schemaVersionValue: String
    public let captureRevisionID: CaptureRevisionID
    public let recordedAtUTC: String
    public let instruments: [MeasurementInstrumentProfile]

    public init(
        captureRevisionID: CaptureRevisionID,
        instruments: [MeasurementInstrumentProfile],
        recordedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws {
        var seen = Set<String>()
        for instrument in instruments {
            let key = instrument.instrumentID.description + "/"
                + String(instrument.profileVersion)
            guard seen.insert(key).inserted else {
                throw FieldAuthorityModelError.duplicateRecord(key)
            }
            guard instrument.verifyDigest() else {
                throw FieldAuthorityModelError.unboundReference(
                    "profile_sha256"
                )
            }
        }
        guard SchemaTimestampText.isUTCTimestamp(recordedAtUTC) else {
            throw FieldAuthorityModelError
                .invalidTimestamp(recordedAtUTC)
        }
        self.schemaName = Self.schema
        self.schemaVersionValue = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.recordedAtUTC = recordedAtUTC
        self.instruments = instruments
    }

    /// Latest committed version of `instrumentID`, if any.
    public func latestVersion(of instrumentID: InstrumentProfileID)
        -> Int?
    {
        instruments
            .filter { $0.instrumentID == instrumentID }
            .map(\.profileVersion)
            .max()
    }

    public func profile(
        matching reference: MeasurementInstrumentReference
    ) -> MeasurementInstrumentProfile? {
        instruments.first {
            $0.instrumentID == reference.instrumentID
                && $0.profileVersion == reference.profileVersion
                && $0.profileSHA256 == reference.profileSHA256
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaName = "schema"
        case schemaVersionValue = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case recordedAtUTC = "recorded_at_utc"
        case instruments
    }
}

/// Encoded `InstrumentProfileDocument` ready for the working-set store.
public struct InstrumentProfilePackage: Sendable, Equatable {
    public static let path = "derived/instrument-profiles.json"
    public static let sourceRef = "path:" + path

    public let document: InstrumentProfileDocument
    public let data: Data
    public let sourceRefs: [String]

    public init(document: InstrumentProfileDocument) throws {
        var refs = Set<String>()
        for instrument in document.instruments {
            for ref in instrument.calibrationEvidenceRefs
            where ref.hasPrefix("path:")
                || ref.hasPrefix("frame:")
            {
                if ref.hasPrefix("frame:") {
                    refs.insert(
                        "path:evidence/frames/"
                            + ref.dropFirst("frame:".count)
                            + ".json"
                    )
                } else {
                    refs.insert(ref)
                }
            }
        }
        refs.insert("path:" + MeasurementEvidencePackage.path)
        self.document = document
        self.sourceRefs = refs.sorted()
        self.data = try FieldAuthorityCoding.encoder()
            .encode(document)
    }
}
