import Foundation

/// Advisory on-device Evidence Image Quality Preflight (#407).
///
/// A persisted still image can be cryptographically valid evidence
/// while being operationally useless — motion blur, glare over a
/// serial label, under/over-exposure, or a subject too small to read.
/// This contract produces one reusable, task-profile-aware, advisory
/// assessment per exact image so capture flows can offer
/// Retake / Use-anyway before the operator leaves the room.
///
/// Boundaries that keep the gate honest:
///
///   * Derived/advisory metadata — the assessment never alters or
///     replaces canonical captured bytes, never blocks finalization,
///     and never claims semantic verification.
///   * Distinct from recognition confidence, catalog-match confidence
///     and operator confirmation (#407 §8): those live on the scan
///     result / identity record, not here.
///   * Image quality is per-image: a retake gets a fresh assessment;
///     re-evaluation under a new algorithm produces a new derived
///     record, never a rewrite.
///   * On-device and bounded: the evaluator consumes cheap pixel
///     statistics (`FrameUsabilityMetrics`) plus optional recognizer
///     signals; it never runs on AR capture callbacks and reports
///     `unknown` — never a pass — when analysis was unavailable.
///
/// Authority class: `.captureDerivedDiagnostic` (#405) — the artifact
/// is derived acquisition evidence, not observed truth.
public enum EvidenceImageQualityProfile: String, Codable, Sendable, CaseIterable {
    /// Serial/model label evidence: text/barcode size, sharpness,
    /// glare and crop dominate (#407 §2).
    case equipmentLabel = "equipment_label"
    /// Installed-settings screen: focus, display glare, full UI in
    /// frame, readable text.
    case installedSettings = "installed_settings"
    /// Wiring/route evidence: connector area in frame, sufficient
    /// focus; label legibility evaluated when the task requires it.
    case wiringEvidence = "wiring_evidence"
    /// General field photo: broad photographic usability only —
    /// no label-OCR requirement.
    case generalPhoto = "general_photo"

    /// Whether this profile always evaluates text/barcode legibility.
    public var requiresLegibility: Bool {
        self == .equipmentLabel || self == .installedSettings
    }
}

/// Per-domain categorical outcome — deliberately coarse so the UI
/// presents "Looks sharp / May be blurred / Unknown" rather than an
/// internal metric (#407 §3).
public enum EvidenceImageQualityVerdict: String, Codable, Sendable {
    case pass
    case warning
    /// Evaluated but the signal was unavailable — never a pass.
    case unknown
}

/// Whole-image advisory status. `unknown` means the assessment could
/// not run (probe unavailable, analysis skipped under thermal load) —
/// it is never reported as a pass (#407 §14).
public enum EvidenceImageQualityStatus: String, Codable, Sendable {
    case usable
    case suspect
    case unknown
}

/// Actionable machine-readable reasons behind a warning status —
/// mapped by the UI to concise retake guidance (#407 §15).
public enum EvidenceImageQualityReason: String, Codable, Sendable {
    case imageTooDark = "image_too_dark"
    case imageOverexposed = "image_overexposed"
    case blurSuspected = "blur_suspected"
    case glareOverSubject = "glare_over_subject"
    case subjectTooSmall = "subject_too_small"
    case subjectCropped = "subject_cropped"
    case textUnreadable = "text_unreadable"
    case barcodeUndetected = "barcode_undetected"
    case assessmentUnavailable = "assessment_unavailable"
}

/// Task-dependent signals supplied by the recognizer/capture flow —
/// all optional; a domain they gate reports `unknown` when the signal
/// is absent rather than pretending it passed (#407 §14).
public struct EvidenceImageTaskMetrics: Sendable, Equatable {
    /// Fraction of the frame covered by the recognized subject region
    /// (label/text), normalized 0...1.
    public let subjectRegionFraction: Double?
    /// Fraction of the subject region at/above the specular clip
    /// bound — glare sitting on the label.
    public let subjectGlareFraction: Double?
    /// Fraction of the subject region below the darkness bound.
    public let subjectDarkFraction: Double?
    /// The recognized subject touches a frame boundary — likely
    /// cropped text (#407 §7).
    public let subjectTouchesFrameEdge: Bool?
    /// Recognizer legibility confidence for the task's text, 0...1.
    public let textLegibility: Double?
    /// A barcode/QR payload decoded for the task. Explicit `false`
    /// means the task looked for one and found none.
    public let barcodeDetected: Bool?
    /// Captured pixel dimensions, when known.
    public let pixelWidth: Int?
    public let pixelHeight: Int?

    public init(
        subjectRegionFraction: Double? = nil,
        subjectGlareFraction: Double? = nil,
        subjectDarkFraction: Double? = nil,
        subjectTouchesFrameEdge: Bool? = nil,
        textLegibility: Double? = nil,
        barcodeDetected: Bool? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.subjectRegionFraction = subjectRegionFraction
        self.subjectGlareFraction = subjectGlareFraction
        self.subjectDarkFraction = subjectDarkFraction
        self.subjectTouchesFrameEdge = subjectTouchesFrameEdge
        self.textLegibility = textLegibility
        self.barcodeDetected = barcodeDetected
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// The shared assessment contract (#407 §1). Codable so it can ride
/// as derived metadata; it is per-image (`evidenceRef` binds the exact
/// canonical bytes) and carries the algorithm version that produced
/// it so a later algorithm yields a *new* derived record.
public struct EvidenceImageQualityAssessment: Codable, Sendable, Equatable {
    public static let expectedSchema =
        "htdt.capture.evidence-image-quality"
    public static let expectedAssessmentVersion = "1.0.0"

    public let schema: String
    /// Assessment contract version (the *contract*, distinct from the
    /// `algorithmVersion` that produced the verdicts).
    public let assessmentVersion: String
    /// Evidence ref of the exact image assessed (`path:`/`frame:`).
    public let evidenceRef: String
    public let profile: EvidenceImageQualityProfile
    /// #405 authority class — always `capture_derived_diagnostic`.
    public let authorityClass: CaptureAuthorityClass
    public let sharpness: EvidenceImageQualityVerdict
    public let exposure: EvidenceImageQualityVerdict
    /// nil = not evaluated under this profile/metric set.
    public let glare: EvidenceImageQualityVerdict?
    public let framing: EvidenceImageQualityVerdict?
    public let legibility: EvidenceImageQualityVerdict?
    public let status: EvidenceImageQualityStatus
    public let reasons: [EvidenceImageQualityReason]
    /// Bounded pixel statistics the verdicts were computed from.
    public let metrics: FrameUsabilityMetrics?
    /// Which algorithm produced the verdicts.
    public let algorithm: String
    public let algorithmVersion: String
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    /// Free-form device context (e.g. model family), when known.
    public let deviceContext: String?
    public let createdAtUTC: String

    public init(
        schema: String = Self.expectedSchema,
        assessmentVersion: String = Self.expectedAssessmentVersion,
        evidenceRef: String,
        profile: EvidenceImageQualityProfile,
        authorityClass: CaptureAuthorityClass =
            .captureDerivedDiagnostic,
        sharpness: EvidenceImageQualityVerdict,
        exposure: EvidenceImageQualityVerdict,
        glare: EvidenceImageQualityVerdict? = nil,
        framing: EvidenceImageQualityVerdict? = nil,
        legibility: EvidenceImageQualityVerdict? = nil,
        status: EvidenceImageQualityStatus,
        reasons: [EvidenceImageQualityReason],
        metrics: FrameUsabilityMetrics? = nil,
        algorithm: String,
        algorithmVersion: String,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        deviceContext: String? = nil,
        createdAtUTC: String
    ) throws {
        guard SchemaOwnedText.nfc(evidenceRef) == evidenceRef,
              !evidenceRef.isEmpty
        else {
            throw AnnotationModelError.emptyAuthorityReference
        }
        guard SchemaTimestampText.isUTCTimestamp(createdAtUTC) else {
            throw AnnotationModelError.invalidTimestamp
        }
        self.schema = schema
        self.assessmentVersion = assessmentVersion
        self.evidenceRef = evidenceRef
        self.profile = profile
        self.authorityClass = authorityClass
        self.sharpness = sharpness
        self.exposure = exposure
        self.glare = glare
        self.framing = framing
        self.legibility = legibility
        self.status = status
        self.reasons = reasons
        self.metrics = metrics
        self.algorithm = algorithm
        self.algorithmVersion = algorithmVersion
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.deviceContext = deviceContext
        self.createdAtUTC = createdAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case assessmentVersion = "assessment_version"
        case evidenceRef = "evidence_ref"
        case profile
        case authorityClass = "authority_class"
        case sharpness
        case exposure
        case glare
        case framing
        case legibility
        case status
        case reasons
        case metrics
        case algorithm
        case algorithmVersion = "algorithm_version"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
        case deviceContext = "device_context"
        case createdAtUTC = "created_at_utc"
    }
}

/// Deterministic still-image usability checks (#407 IMGQ-20):
/// sharpness, exposure/clipping, subject framing and legibility over
/// bounded metrics. Pure — same inputs produce the same verdicts;
/// the versioned `algorithmVersion` records what measured them.
public struct EvidenceImageQualityEvaluator: Sendable, Equatable {
    /// Versioned diagnostic identity so persisted assessments record
    /// exactly which algorithm generation produced them.
    public static let algorithm = "evidence-image-quality-evaluator"
    public static let algorithmVersion = "evidence_image_quality_v1"

    /// Mean luma below which the image is too dark to be evidence.
    public let darkMeanThreshold: Double
    /// Sampled darkness fraction above which the image is too dark.
    public let unusableDarkFraction: Double
    /// Clipped (near-white) fraction above which exposure is suspect.
    public let clippedFractionThreshold: Double
    /// Mean luma-gradient energy below which blur is suspected.
    public let blurGradientThreshold: Double
    /// EXIF exposure duration above which handheld blur is suspected.
    public let longExposureSeconds: Double
    /// Subject-region fraction below which a label is too small to
    /// read reliably.
    public let subjectMinFraction: Double
    /// Specular fraction over the subject region at which glare is
    /// likely obscuring the label.
    public let subjectGlareThreshold: Double
    /// Subject darkness fraction at which the label reads too dark.
    public let subjectDarkThreshold: Double
    /// Recognizer legibility floor for readable text.
    public let legibilityFloor: Double

    public init(
        darkMeanThreshold: Double = 0.06,
        unusableDarkFraction: Double = 0.7,
        clippedFractionThreshold: Double = 0.5,
        blurGradientThreshold: Double = 0.004,
        longExposureSeconds: Double = 0.05,
        subjectMinFraction: Double = 0.01,
        subjectGlareThreshold: Double = 0.15,
        subjectDarkThreshold: Double = 0.5,
        legibilityFloor: Double = 0.5
    ) {
        self.darkMeanThreshold = darkMeanThreshold
        self.unusableDarkFraction = unusableDarkFraction
        self.clippedFractionThreshold = clippedFractionThreshold
        self.blurGradientThreshold = blurGradientThreshold
        self.longExposureSeconds = longExposureSeconds
        self.subjectMinFraction = subjectMinFraction
        self.subjectGlareThreshold = subjectGlareThreshold
        self.subjectDarkThreshold = subjectDarkThreshold
        self.legibilityFloor = legibilityFloor
    }

    /// Assess one exact image for an intended evidence task.
    ///
    /// `base` carries bounded frame statistics from the pixel probe —
    /// nil means the image could not be measured and the assessment
    /// reports `unknown` rather than passing (#407 §14). `task`
    /// supplies recognizer-side signals (subject region, legibility,
    /// barcode) when the capture flow ran recognition.
    public func assess(
        base: FrameUsabilityMetrics?,
        task: EvidenceImageTaskMetrics?,
        profile: EvidenceImageQualityProfile,
        evidenceRef: String,
        deviceContext: String? = nil,
        createdAtUTC: String
    ) throws -> EvidenceImageQualityAssessment {
        var reasons: [EvidenceImageQualityReason] = []

        let sharpness: EvidenceImageQualityVerdict
        let exposure: EvidenceImageQualityVerdict
        if let base {
            var sharp = true
            let blurByGradient =
                base.gradientEnergy <= blurGradientThreshold
            let blurByExposure =
                (base.exposureSeconds ?? 0) >= longExposureSeconds
                && base.gradientEnergy <= blurGradientThreshold * 2
            if blurByGradient || blurByExposure {
                reasons.append(.blurSuspected)
                sharp = false
            }
            sharpness = sharp ? .pass : .warning

            var exposed = true
            if base.darkFraction >= unusableDarkFraction
                || base.meanLuminance <= darkMeanThreshold
                || (task?.subjectDarkFraction ?? 0)
                    >= subjectDarkThreshold
            {
                reasons.append(.imageTooDark)
                exposed = false
            }
            if base.clippedFraction >= clippedFractionThreshold {
                reasons.append(.imageOverexposed)
                exposed = false
            }
            exposure = exposed ? .pass : .warning
        } else {
            sharpness = .unknown
            exposure = .unknown
        }

        // Glare is evaluated when a subject region was measured; a
        // large clipped frame is already covered by `exposure`.
        let glare: EvidenceImageQualityVerdict?
        if let subjectGlare = task?.subjectGlareFraction {
            if subjectGlare >= subjectGlareThreshold {
                reasons.append(.glareOverSubject)
                glare = .warning
            } else {
                glare = .pass
            }
        } else {
            glare = profile.requiresLegibility ? .unknown : nil
        }

        // Framing needs a recognized subject region: too small to
        // read, or cropped at the frame edge (#407 §7).
        let framing: EvidenceImageQualityVerdict?
        if task?.subjectRegionFraction != nil
            || task?.subjectTouchesFrameEdge != nil
        {
            var framed = true
            if let fraction = task?.subjectRegionFraction,
               fraction < subjectMinFraction
            {
                reasons.append(.subjectTooSmall)
                framed = false
            }
            if task?.subjectTouchesFrameEdge == true {
                reasons.append(.subjectCropped)
                framed = false
            }
            framing = framed ? .pass : .warning
        } else {
            framing = profile.requiresLegibility ? .unknown : nil
        }

        // Legibility: required profiles evaluate it always; wiring
        // evidence evaluates only when the task supplied signals.
        let hasLegibilitySignals = task?.textLegibility != nil
            || task?.barcodeDetected != nil
        let legibility: EvidenceImageQualityVerdict?
        if profile.requiresLegibility || hasLegibilitySignals {
            var readable = true
            var evaluated = false
            if let textLegibility = task?.textLegibility {
                evaluated = true
                if textLegibility < legibilityFloor {
                    reasons.append(.textUnreadable)
                    readable = false
                }
            }
            if task?.barcodeDetected == false {
                evaluated = true
                reasons.append(.barcodeUndetected)
                readable = false
            }
            legibility = evaluated
                ? (readable ? .pass : .warning)
                : .unknown
        } else {
            legibility = nil
        }

        let status: EvidenceImageQualityStatus
        if base == nil && task == nil {
            // Analysis unavailable — never pretend it passed.
            reasons.append(.assessmentUnavailable)
            status = .unknown
        } else if reasons.contains(where: { $0 != .assessmentUnavailable }) {
            status = .suspect
        } else {
            status = .usable
        }

        return try EvidenceImageQualityAssessment(
            evidenceRef: evidenceRef,
            profile: profile,
            sharpness: sharpness,
            exposure: exposure,
            glare: glare,
            framing: framing,
            legibility: legibility,
            status: status,
            reasons: reasons,
            metrics: base,
            algorithm: Self.algorithm,
            algorithmVersion: Self.algorithmVersion,
            pixelWidth: task?.pixelWidth,
            pixelHeight: task?.pixelHeight,
            deviceContext: deviceContext,
            createdAtUTC: createdAtUTC
        )
    }
}
