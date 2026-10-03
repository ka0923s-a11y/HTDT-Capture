import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Bounded fact codes (legacy bolph71656-ai/HTDT-Capture#270)

/// Closed set of evidence-channel tokens a generated identity
/// suggestion may cite. The validator rejects codes outside this set so
/// a model can never invent an evidence channel (issue bolph71656-ai/HTDT-Capture#270).
public enum EquipmentIdentityBasisCode:
    String,
    Codable,
    Sendable,
    Equatable,
    Hashable,
    CaseIterable
{
    case ocrStringMatch = "ocr_string_match"
    case barcodePayload = "barcode_payload"
    case visualBrandMark = "visual_brand_mark"
    case catalogRetrieval = "catalog_retrieval"
}

/// Closed equipment-category tokens for the advisory suggestion. Kept
/// deliberately small and orthogonal to `AnnotationEntityType`: the
/// model may only claim from this set, never a free-form class name.
public enum EquipmentIdentityCategory:
    String,
    Codable,
    Sendable,
    Equatable,
    Hashable,
    CaseIterable
{
    case speaker
    case subwoofer
    case display
    case projector
    case projectionScreen = "projection_screen"
    case equipmentRack = "equipment_rack"
    case avComponent = "av_component"
    case other
}

// MARK: - Structured suggestion (legacy bolph71656-ai/HTDT-Capture#270, advisory only)

/// The model's structured answer for one label scan. Advisory only:
/// nothing in a suggestion is ever written back over a raw OCR/barcode
/// observation, and `needsOperatorConfirmation` is required to be true —
/// a suggestion claiming authority is rejected by the validator.
public struct EquipmentIdentitySuggestion: Sendable, Equatable {
    public let manufacturer: String?
    public let model: String?
    public let serialOrAssetTag: String?
    public let category: EquipmentIdentityCategory?
    /// Catalog selection keys the suggestion points at. Must be a
    /// subset of the bounded catalog slice the model was shown.
    public let matchingCatalogSelectionKeys: [String]
    /// Exact raw observed strings this suggestion cites — membership
    /// in the bounded context's observation list, verified by the
    /// validator. Not the same as "raw strings the matcher used".
    public let evidenceLinks: [String]
    public let basisCodes: [EquipmentIdentityBasisCode]
    public let ambiguityReason: String?
    /// Free-text advisory note (e.g. "OCR read 'AVC-X4800H'; catalog
    /// carries 'AVR-X4800H'"). Length-bounded and never authoritative —
    /// it cannot rewrite the raw observations it cites.
    public let advisoryNote: String?
    public let needsOperatorConfirmation: Bool

    public init(
        manufacturer: String? = nil,
        model: String? = nil,
        serialOrAssetTag: String? = nil,
        category: EquipmentIdentityCategory? = nil,
        matchingCatalogSelectionKeys: [String] = [],
        evidenceLinks: [String] = [],
        basisCodes: [EquipmentIdentityBasisCode] = [],
        ambiguityReason: String? = nil,
        advisoryNote: String? = nil,
        needsOperatorConfirmation: Bool = true
    ) {
        self.manufacturer = manufacturer
        self.model = model
        self.serialOrAssetTag = serialOrAssetTag
        self.category = category
        self.matchingCatalogSelectionKeys =
            matchingCatalogSelectionKeys
        self.evidenceLinks = evidenceLinks
        self.basisCodes = basisCodes
        self.ambiguityReason = ambiguityReason
        self.advisoryNote = advisoryNote
        self.needsOperatorConfirmation = needsOperatorConfirmation
    }

    /// True when the suggestion asserts nothing at all — treated as a
    /// clean abstention rather than a validator rejection.
    public var isVacuous: Bool {
        manufacturer == nil
            && model == nil
            && serialOrAssetTag == nil
            && category == nil
            && matchingCatalogSelectionKeys.isEmpty
    }
}

// MARK: - Bounded context (legacy bolph71656-ai/HTDT-Capture#270)

/// Length/quantity caps applied while building the model's context.
/// The 4096-token window also carries instructions, schema, and output,
/// so input curation is deliberately tight; Japanese/CJK text costs
/// roughly one token per character, which is why every field is
/// length-capped.
public struct EquipmentIdentityAIBudget: Sendable, Equatable {
    /// Apple's documented on-device session window (legacy bolph71656-ai/HTDT-Capture#270). `contextSize`
    /// on the model is only readable on iOS 27+ runtimes from
    /// dual-SDK-safe code paths, so the budget is planned against this
    /// floor regardless.
    public static let contextWindowTokens = 4096

    public var maxObservations: Int
    public var maxObservationLength: Int
    public var maxCandidates: Int
    public var maxCatalogEntries: Int
    public var maxCatalogFieldLength: Int
    public var maxAdvisoryNoteLength: Int
    /// Reserved output/schema headroom inside the 4096-token window;
    /// prompt+instructions must fit under `contextWindow - headroom`.
    public var outputHeadroomTokens: Int

    public init(
        maxObservations: Int,
        maxObservationLength: Int,
        maxCandidates: Int,
        maxCatalogEntries: Int,
        maxCatalogFieldLength: Int,
        maxAdvisoryNoteLength: Int,
        outputHeadroomTokens: Int
    ) {
        self.maxObservations = maxObservations
        self.maxObservationLength = maxObservationLength
        self.maxCandidates = maxCandidates
        self.maxCatalogEntries = maxCatalogEntries
        self.maxCatalogFieldLength = maxCatalogFieldLength
        self.maxAdvisoryNoteLength = maxAdvisoryNoteLength
        self.outputHeadroomTokens = outputHeadroomTokens
    }

    public static let `default` = EquipmentIdentityAIBudget(
        maxObservations: 24,
        maxObservationLength: 64,
        maxCandidates: 3,
        maxCatalogEntries: 8,
        maxCatalogFieldLength: 48,
        maxAdvisoryNoteLength: 240,
        outputHeadroomTokens: 1024
    )

    /// Retry tier after a context-size failure: fewer observations,
    /// shorter fields, smaller catalog slice.
    public static let reduced = EquipmentIdentityAIBudget(
        maxObservations: 12,
        maxObservationLength: 48,
        maxCandidates: 2,
        maxCatalogEntries: 5,
        maxCatalogFieldLength: 36,
        maxAdvisoryNoteLength: 160,
        outputHeadroomTokens: 1024
    )
}

/// A catalog entry reduced to the fields a suggestion may reference —
/// the model never sees the whole catalog, only this bounded slice
/// (legacy bolph71656-ai/HTDT-Capture#270: deterministic retrieval first, no free-form RAG).
public struct EquipmentIdentityAICatalogEntry:
    Sendable,
    Equatable,
    Hashable
{
    public let selectionKey: String
    public let manufacturer: String?
    public let model: String?
    public let userLabel: String?
}

/// A deterministic-matcher candidate reduced to display fields.
public struct EquipmentIdentityAICandidateDigest:
    Sendable,
    Equatable,
    Hashable
{
    public let catalogSelectionKey: String?
    public let manufacturer: String?
    public let model: String?
    public let serialOrAssetTag: String?
    public let confidence: Float
}

/// Everything the model is allowed to know for one identity attempt:
/// the raw observations, the deterministic matcher's candidates, a
/// bounded catalog slice, and provenance identifiers. Built by the
/// deterministic layer — the model only ranks/explains inside it.
public struct EquipmentIdentityAIContext: Sendable, Equatable {
    public let evidenceRef: String
    public let rawObservations: [String]
    public let deterministicCandidates:
        [EquipmentIdentityAICandidateDigest]
    public let catalogSlice: [EquipmentIdentityAICatalogEntry]
    public let catalogContentSHA256: String?
    public let matcherAlgorithm: String
    public let matcherVersion: String
    public let budget: EquipmentIdentityAIBudget

    public init(
        result: EquipmentLabelScanResult,
        catalog: [HTDTEquipmentCatalogEntry],
        catalogContentSHA256: String?,
        budget: EquipmentIdentityAIBudget = .default
    ) {
        self.evidenceRef = result.evidenceRef
        self.matcherAlgorithm = result.algorithm
        self.matcherVersion = result.algorithmVersion
        self.catalogContentSHA256 = catalogContentSHA256
        self.budget = budget

        var seen: Set<String> = []
        var observations: [String] = []
        for raw in result.rawObservations {
            let trimmed = String(raw.prefix(budget.maxObservationLength))
            if seen.insert(trimmed).inserted {
                observations.append(trimmed)
            }
            if observations.count >= budget.maxObservations { break }
        }
        self.rawObservations = observations

        self.deterministicCandidates = result.candidates
            .prefix(budget.maxCandidates)
            .map {
                EquipmentIdentityAICandidateDigest(
                    catalogSelectionKey: $0.catalogSelectionKey,
                    manufacturer: $0.manufacturer,
                    model: $0.model,
                    serialOrAssetTag: $0.serialOrAssetTag,
                    confidence: $0.confidence
                )
            }

        // Bounded deterministic retrieval: an entry enters the slice
        // only when a deterministic candidate already resolved to it or
        // its normalized model/definition ID appears inside a raw
        // observation. Catalog order is preserved so the slice is
        // reproducible for the same inputs.
        let candidateKeys = Set(
            result.candidates.compactMap(\.catalogSelectionKey)
        )
        let normalizedObservations = observations.map(
            EquipmentLabelScanMatcher.normalize
        )
        var slice: [EquipmentIdentityAICatalogEntry] = []
        for entry in catalog {
            if slice.count >= budget.maxCatalogEntries { break }
            let keyed = candidateKeys.contains(entry.selectionKey)
            let normalizedID = EquipmentLabelScanMatcher.normalize(
                entry.definitionID
            )
            let normalizedModel = entry.model.map(
                EquipmentLabelScanMatcher.normalize
            ) ?? ""
            let textHit = normalizedObservations.contains { text in
                (!normalizedID.isEmpty && text.contains(normalizedID))
                    || (normalizedModel.count >= 3
                        && text.contains(normalizedModel))
            }
            guard keyed || textHit else { continue }
            slice.append(
                EquipmentIdentityAICatalogEntry(
                    selectionKey: entry.selectionKey,
                    manufacturer: entry.manufacturer.map {
                        String($0.prefix(budget.maxCatalogFieldLength))
                    },
                    model: entry.model.map {
                        String($0.prefix(budget.maxCatalogFieldLength))
                    },
                    userLabel: entry.userLabel.map {
                        String($0.prefix(budget.maxCatalogFieldLength))
                    }
                )
            )
        }
        self.catalogSlice = slice
    }
}

// MARK: - Prompt composition (legacy bolph71656-ai/HTDT-Capture#270)

/// Deterministic, versioned prompt/instruction text for the bounded
/// identity task. Instructions stay in compact English: output fields
/// are tokens/strings rather than prose, and Japanese instruction text
/// would spend the small window ~1 token per CJK character for no gain.
public enum EquipmentIdentityAIPrompt {
    /// Bumped whenever instructions, prompt layout, or the bounded
    /// context shape change — recorded in provenance so evaluations can
    /// separate prompt revisions from model behavior.
    public static let promptRevision = "equipment-identity-ai/1.0"

    public static func instructions() -> String {
        """
        You help identify home-theater equipment from a label scan. \
        Suggest an identity only from the raw observations and the \
        catalog slice provided. Never invent identifiers. Serial and \
        asset tags stay verbatim. If the evidence is ambiguous or \
        insufficient, leave fields empty and explain in \
        ambiguityReason. needsOperatorConfirmation must always be true.
        """
    }

    /// Compact labeled blocks: OBS (raw observed strings), MATCH
    /// (deterministic candidates), CAT (bounded catalog slice). Every
    /// block is already length-capped by the context builder.
    public static func prompt(
        for context: EquipmentIdentityAIContext
    ) -> String {
        var lines: [String] = ["OBS:"]
        for observation in context.rawObservations {
            lines.append("- " + observation)
        }
        lines.append("MATCH:")
        for candidate in context.deterministicCandidates {
            var fields: [String] = []
            if let key = candidate.catalogSelectionKey {
                fields.append("key=" + key)
            }
            if let manufacturer = candidate.manufacturer {
                fields.append("mfr=" + manufacturer)
            }
            if let model = candidate.model {
                fields.append("model=" + model)
            }
            if let serial = candidate.serialOrAssetTag {
                fields.append("serial=" + serial)
            }
            fields.append(
                "conf="
                    + String(format: "%.2f", candidate.confidence)
            )
            lines.append("- " + fields.joined(separator: " | "))
        }
        lines.append("CAT:")
        for entry in context.catalogSlice {
            var fields = ["key=" + entry.selectionKey]
            if let manufacturer = entry.manufacturer {
                fields.append("mfr=" + manufacturer)
            }
            if let model = entry.model {
                fields.append("model=" + model)
            }
            if let label = entry.userLabel {
                fields.append("label=" + label)
            }
            lines.append("- " + fields.joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }

    /// Conservative estimate used only when the API's tokenCount is not
    /// readable (pre-iOS-27 runtimes): ~1 token per CJK scalar (Apple's
    /// guidance), ~1 per 4 remaining scalars. Deliberately biased high
    /// so the preflight budget check stays honest.
    public static func estimatedTokens(_ text: String) -> Int {
        var count = 0
        for scalar in text.unicodeScalars {
            // CJK Unified + Hiragana/Katakana/Hangul ranges.
            let isCJK =
                (0x1100...0x11FF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
            count += isCJK ? 4 : 1
        }
        return (count + 3) / 4
    }
}

// MARK: - Deterministic validator (legacy bolph71656-ai/HTDT-Capture#270)

/// A single grounding violation found in a generated suggestion.
public enum EquipmentIdentityAIViolation:
    String,
    Sendable,
    Equatable,
    Hashable,
    CaseIterable
{
    /// Suggestion claimed authority (`needsOperatorConfirmation == false`).
    case confirmationNotRequired
    /// A catalog selection key outside the bounded slice the model saw.
    case unknownCatalogKey
    /// An evidence link that is not a raw observed string.
    case unknownEvidenceLink
    /// A basis code outside the closed token set.
    case unknownBasisCode
    /// A category token outside the closed set.
    case unknownCategory
    /// Manufacturer not grounded in observations/candidates/slice.
    case ungroundedManufacturer
    /// Model not grounded in observations/candidates/slice.
    case ungroundedModel
    /// Serial not grounded in raw observations (serials never come
    /// from the catalog slice).
    case ungroundedSerial
    /// Advisory note exceeded the length bound.
    case oversizedAdvisoryNote
}

/// The deterministic gate between model output and advisory display
/// (legacy bolph71656-ai/HTDT-Capture#270): every claim must trace to the bounded context — a raw
/// observation, a deterministic candidate, or the catalog slice —
/// else the suggestion is rejected wholesale. Rejection is a normal
/// outcome, not an error.
public enum EquipmentIdentityAIValidator {

    public static func violations(
        in suggestion: EquipmentIdentitySuggestion,
        context: EquipmentIdentityAIContext,
        budget: EquipmentIdentityAIBudget = .default
    ) -> [EquipmentIdentityAIViolation] {
        var violations: Set<EquipmentIdentityAIViolation> = []

        if !suggestion.needsOperatorConfirmation {
            violations.insert(.confirmationNotRequired)
        }

        let sliceKeys = Set(
            context.catalogSlice.map(\.selectionKey)
        )
        for key in suggestion.matchingCatalogSelectionKeys
        where !sliceKeys.contains(key) {
            violations.insert(.unknownCatalogKey)
        }

        let rawSet = Set(context.rawObservations)
        for link in suggestion.evidenceLinks where !rawSet.contains(link)
        {
            violations.insert(.unknownEvidenceLink)
        }

        // Normalized claim universe: identity fields may cite raw
        // observations (exact or substring after normalization),
        // deterministic candidates, or catalog-slice fields.
        var grounded: Set<String> = []
        var normalizedRaw: [String] = []
        for raw in context.rawObservations {
            let normalized = EquipmentLabelScanMatcher.normalize(raw)
            normalizedRaw.append(normalized)
            if !normalized.isEmpty { grounded.insert(normalized) }
        }
        var sliceManufacturers: Set<String> = []
        var sliceModels: Set<String> = []
        for entry in context.catalogSlice {
            if let manufacturer = entry.manufacturer {
                sliceManufacturers.insert(
                    EquipmentLabelScanMatcher.normalize(manufacturer)
                )
            }
            if let model = entry.model {
                sliceModels.insert(
                    EquipmentLabelScanMatcher.normalize(model)
                )
            }
        }
        for candidate in context.deterministicCandidates {
            for field in [
                candidate.manufacturer, candidate.model,
                candidate.serialOrAssetTag,
            ] {
                if let field {
                    let normalized =
                        EquipmentLabelScanMatcher.normalize(field)
                    if !normalized.isEmpty {
                        grounded.insert(normalized)
                    }
                }
            }
        }

        func groundedClaim(_ claim: String?) -> Bool? {
            guard let claim else { return nil }
            let normalized = EquipmentLabelScanMatcher.normalize(claim)
            guard !normalized.isEmpty else { return false }
            return grounded.contains(normalized)
                || normalizedRaw.contains { $0.contains(normalized) }
        }

        if let grounded = groundedClaim(suggestion.manufacturer) {
            if !grounded,
               let normalized = suggestion.manufacturer.map(
                   EquipmentLabelScanMatcher.normalize
               ), !sliceManufacturers.contains(normalized) {
                violations.insert(.ungroundedManufacturer)
            }
        }
        if let grounded = groundedClaim(suggestion.model) {
            if !grounded,
               let normalized = suggestion.model.map(
                   EquipmentLabelScanMatcher.normalize
               ), !sliceModels.contains(normalized) {
                violations.insert(.ungroundedModel)
            }
        }
        // Serials are evidence-only: grounded solely in raw
        // observations, never in the catalog slice.
        if let serial = suggestion.serialOrAssetTag {
            let normalized =
                EquipmentLabelScanMatcher.normalize(serial)
            let grounded =
                !normalized.isEmpty
                && normalizedRaw.contains { $0.contains(normalized) }
            if !grounded {
                violations.insert(.ungroundedSerial)
            }
        }
        if let note = suggestion.advisoryNote,
           note.count > budget.maxAdvisoryNoteLength {
            violations.insert(.oversizedAdvisoryNote)
        }

        return EquipmentIdentityAIViolation.allCases.filter {
            violations.contains($0)
        }
    }
}

// MARK: - Result / provenance (legacy bolph71656-ai/HTDT-Capture#270)

public enum EquipmentIdentityAIStatus:
    String,
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    /// Validator-approved suggestion produced.
    case suggested
    /// Model produced a vacuous suggestion — a clean abstention.
    case abstained
    /// Framework/model unavailable on this device (Simulator included).
    case unavailable
    /// Operator/output locale not in the model's supported languages.
    case localeUnsupported = "locale_unsupported"
    /// Prompt did not fit the context window even at reduced budget.
    case contextOverflow = "context_overflow"
    /// Suggestion failed deterministic grounding validation.
    case validatorRejected = "validator_rejected"
    /// Generation threw (any cause incl. context errors whose specific
    /// case is not nameable under the build SDK).
    case generationFailed = "generation_failed"
}

/// What the API actually exposed for one suggestion attempt (legacy bolph71656-ai/HTDT-Capture#270
/// provenance): availability, OS, locale, context size, prompt revision,
/// catalog revision, matcher version. `modelVariant` stays nil on
/// builds where the SDK does not expose `SystemLanguageModel.variant`
/// (iOS 26.x SDK) — an invented model ID is never recorded.
public struct EquipmentIdentityAIProvenance:
    Sendable,
    Equatable,
    Hashable
{
    public let promptRevision: String
    /// `available` or `unavailable(<reason-case-name>)`.
    public let modelAvailability: String
    /// `SystemLanguageModel.variant` is only declared by the iOS 27
    /// SDK; it cannot be referenced in code that also compiles against
    /// the iOS 26 SDK, so this stays nil there rather than fabricated.
    public let modelVariant: String?
    public let osVersion: String
    public let localeIdentifier: String
    /// Nil when `supportedLanguages` could not be consulted.
    public let supportedLocale: Bool?
    /// Runtime-read `contextSize` (iOS 27+ from a dual-SDK build);
    /// nil otherwise — the budget uses the documented 4096 floor.
    public let contextSizeTokens: Int?
    public let estimatedPromptTokens: Int
    /// `tokenCount(for:)` measurement (iOS 27+); nil when unreadable.
    public let measuredPromptTokens: Int?
    public let catalogContentSHA256: String?
    public let matcherAlgorithm: String
    public let matcherVersion: String
    /// 1 = first pass, 2 = single bounded retry at reduced budget.
    public let attempts: Int

    public init(
        promptRevision: String,
        modelAvailability: String,
        modelVariant: String? = nil,
        osVersion: String,
        localeIdentifier: String,
        supportedLocale: Bool?,
        contextSizeTokens: Int? = nil,
        estimatedPromptTokens: Int,
        measuredPromptTokens: Int? = nil,
        catalogContentSHA256: String?,
        matcherAlgorithm: String,
        matcherVersion: String,
        attempts: Int
    ) {
        self.promptRevision = promptRevision
        self.modelAvailability = modelAvailability
        self.modelVariant = modelVariant
        self.osVersion = osVersion
        self.localeIdentifier = localeIdentifier
        self.supportedLocale = supportedLocale
        self.contextSizeTokens = contextSizeTokens
        self.estimatedPromptTokens = estimatedPromptTokens
        self.measuredPromptTokens = measuredPromptTokens
        self.catalogContentSHA256 = catalogContentSHA256
        self.matcherAlgorithm = matcherAlgorithm
        self.matcherVersion = matcherVersion
        self.attempts = attempts
    }
}

/// The advisory-lane outcome for one scan — a suggestion only ever
/// rides alongside the untouched deterministic result; any status other
/// than `.suggested` means the operator sees no new information.
public struct EquipmentIdentityAIResult: Sendable, Equatable {
    public let status: EquipmentIdentityAIStatus
    /// Bounded diagnostic text (error names/status detail), capped and
    /// newline-stripped — never raw model output or secret material.
    public let statusDetail: String?
    public let suggestion: EquipmentIdentitySuggestion?
    public let violations: [EquipmentIdentityAIViolation]
    public let provenance: EquipmentIdentityAIProvenance

    public init(
        status: EquipmentIdentityAIStatus,
        statusDetail: String? = nil,
        suggestion: EquipmentIdentitySuggestion? = nil,
        violations: [EquipmentIdentityAIViolation] = [],
        provenance: EquipmentIdentityAIProvenance
    ) {
        self.status = status
        self.statusDetail = statusDetail.map {
            String($0.replacingOccurrences(of: "\n", with: " ")
                .prefix(160))
        }
        self.suggestion = suggestion
        self.violations = violations
        self.provenance = provenance
    }
}

// MARK: - Foundation Models advisory lane (iOS 26+/macOS 26+)

#if canImport(FoundationModels)

/// The generated-shape mirror of `EquipmentIdentitySuggestion`. Kept
/// private and stringly-typed: unmapped category/basis tokens become
/// validator violations instead of silent decode failures, which is
/// what makes hallucination rejection observable in evaluation.
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct FMEquipmentIdentitySuggestion {
    var manufacturer: String?
    var model: String?
    var serialOrAssetTag: String?
    var category: String?
    var matchingCatalogSelectionKeys: [String] = []
    var evidenceLinks: [String] = []
    var basisCodes: [String] = []
    var ambiguityReason: String?
    var advisoryNote: String?
    var needsOperatorConfirmation: Bool
}

/// One bounded, task-scoped suggestion pass per call (issue bolph71656-ai/HTDT-Capture#270):
/// a fresh `LanguageModelSession`, a deterministically built bounded
/// context, structured generation, then deterministic validation.
/// There is no long-lived transcript, no Dynamic Profile, and no
/// adapter. Every failure mode — model unavailable, unsupported locale,
/// context overflow, generation error, validator rejection — is a
/// normal typed result that leaves the deterministic lane untouched.
@available(iOS 26.0, macOS 26.0, *)
public enum EquipmentIdentityAIAdvisor {

    /// Runs the advisory pass for one label-scan result.
    ///
    /// Availability order: the experimental flag is checked by the
    /// caller before this is invoked; here `SystemLanguageModel`
    /// availability and the supported-locale set are consulted at
    /// runtime so Simulator (`.unavailable`) and ineligible devices
    /// fall through to a typed status without touching the scan result.
    public static func suggest(
        result: EquipmentLabelScanResult,
        catalog: [HTDTEquipmentCatalogEntry],
        catalogContentSHA256: String?,
        locale: Locale = .current
    ) async -> EquipmentIdentityAIResult {
        let model = SystemLanguageModel.default
        let availabilityText: String
        switch model.availability {
        case .available:
            availabilityText = "available"
        case .unavailable(let reason):
            availabilityText = "unavailable(" + reasonName(reason) + ")"
        }

        func provenance(
            estimated: Int,
            measured: Int?,
            contextSize: Int?,
            supported: Bool?,
            attempts: Int
        ) -> EquipmentIdentityAIProvenance {
            EquipmentIdentityAIProvenance(
                promptRevision: EquipmentIdentityAIPrompt.promptRevision,
                modelAvailability: availabilityText,
                modelVariant: nil,
                osVersion: ProcessInfo.processInfo
                    .operatingSystemVersionString,
                localeIdentifier: locale.identifier,
                supportedLocale: supported,
                contextSizeTokens: contextSize,
                estimatedPromptTokens: estimated,
                measuredPromptTokens: measured,
                catalogContentSHA256: catalogContentSHA256,
                matcherAlgorithm: result.algorithm,
                matcherVersion: result.algorithmVersion,
                attempts: attempts
            )
        }

        func early(
            _ status: EquipmentIdentityAIStatus,
            detail: String? = nil,
            supported: Bool? = nil
        ) -> EquipmentIdentityAIResult {
            EquipmentIdentityAIResult(
                status: status,
                statusDetail: detail,
                provenance: provenance(
                    estimated: 0,
                    measured: nil,
                    contextSize: nil,
                    supported: supported,
                    attempts: 0
                )
            )
        }

        guard model.availability == .available else {
            return early(.unavailable, detail: availabilityText)
        }

        let languages = model.supportedLanguages
        if !languages.isEmpty, !languages.contains(locale.language) {
            return early(
                .localeUnsupported,
                detail: locale.identifier,
                supported: false
            )
        }
        let supported: Bool? =
            languages.isEmpty ? nil : true

        // Up to two passes: default budget, then the reduced budget —
        // the documented handling for context-size pressure is a
        // smaller fresh context, never silently dropped evidence (the
        // deterministic result is untouched either way).
        let budgets: [EquipmentIdentityAIBudget] = [.default, .reduced]
        var attempts = 0
        for budget in budgets {
            let context = EquipmentIdentityAIContext(
                result: result,
                catalog: catalog,
                catalogContentSHA256: catalogContentSHA256,
                budget: budget
            )
            let instructions = EquipmentIdentityAIPrompt.instructions()
            let prompt = EquipmentIdentityAIPrompt.prompt(
                for: context
            )
            let estimated =
                EquipmentIdentityAIPrompt.estimatedTokens(instructions)
                + EquipmentIdentityAIPrompt.estimatedTokens(prompt)

            // Preflight the window: instructions+prompt+output must fit
            // inside 4096 with headroom before a session is even made.
            guard estimated
                <= EquipmentIdentityAIBudget.contextWindowTokens
                    - budget.outputHeadroomTokens
            else {
                if budget == budgets.last {
                    return EquipmentIdentityAIResult(
                        status: .contextOverflow,
                        statusDetail:
                            "estimated \(estimated) tokens over window",
                        provenance: provenance(
                            estimated: estimated,
                            measured: nil,
                            contextSize: nil,
                            supported: supported,
                            attempts: attempts
                        )
                    )
                }
                continue
            }

            attempts += 1
            do {
                let session = LanguageModelSession(
                    model: model,
                    tools: [],
                    instructions: instructions
                )
                let response = try await session.respond(
                    to: prompt,
                    generating: FMEquipmentIdentitySuggestion.self
                )

                var measuredTokens: Int?
                var contextSize: Int?
                // `tokenCount(for:)`/`contextSize` are declared iOS 27+
                // in the current SDKs from a dual-SDK-compilable path;
                // on iOS 26.x they stay nil and the estimate stands.
                if #available(iOS 27.0, macOS 27.0, *) {
                    measuredTokens = try? await model.tokenCount(
                        for: session.transcript
                    )
                    contextSize = model.contextSize
                }

                var mappingViolations:
                    [EquipmentIdentityAIViolation] = []
                let suggestion = map(response.content) { violation in
                    mappingViolations.append(violation)
                }

                if suggestion.isVacuous {
                    return EquipmentIdentityAIResult(
                        status: .abstained,
                        suggestion: suggestion,
                        provenance: provenance(
                            estimated: estimated,
                            measured: measuredTokens,
                            contextSize: contextSize,
                            supported: supported,
                            attempts: attempts
                        )
                    )
                }

                let violations =
                    EquipmentIdentityAIValidator.violations(
                        in: suggestion,
                        context: context,
                        budget: budget
                    ) + mappingViolations
                guard violations.isEmpty else {
                    return EquipmentIdentityAIResult(
                        status: .validatorRejected,
                        suggestion: suggestion,
                        violations: violations,
                        provenance: provenance(
                            estimated: estimated,
                            measured: measuredTokens,
                            contextSize: contextSize,
                            supported: supported,
                            attempts: attempts
                        )
                    )
                }
                return EquipmentIdentityAIResult(
                    status: .suggested,
                    suggestion: suggestion,
                    provenance: provenance(
                        estimated: estimated,
                        measured: measuredTokens,
                        contextSize: contextSize,
                        supported: supported,
                        attempts: attempts
                    )
                )
            } catch {
                // Any generation failure (including the context-size
                // case, whose type differs across iOS 26/27 SDKs) is a
                // normal outcome: retry once at the reduced budget,
                // then report.
                if budget == budgets.last {
                    return EquipmentIdentityAIResult(
                        status: isContextSizeError(error)
                            ? .contextOverflow
                            : .generationFailed,
                        statusDetail: String(describing: error),
                        provenance: provenance(
                            estimated: estimated,
                            measured: nil,
                            contextSize: nil,
                            supported: supported,
                            attempts: attempts
                        )
                    )
                }
            }
        }
        // Unreachable: the reduced-tier loop always returns.
        return early(.generationFailed, supported: supported)
    }

    private static func reasonName(
        _ reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "deviceNotEligible"
        case .appleIntelligenceNotEnabled:
            return "appleIntelligenceNotEnabled"
        case .modelNotReady:
            return "modelNotReady"
        default:
            return "other"
        }
    }

    /// True for the context-window error case. `LanguageModelError`
    /// does not exist in the iOS 26 SDK and `GenerationError`'s
    /// exceeded-context case is deprecated in the iOS 27 SDK but still
    /// thrown there by sessions created against that runtime, so this
    /// path matches whichever spelling the running SDK surfaces without
    /// ever referencing a symbol the other SDK lacks.
    private static func isContextSizeError(_ error: Error) -> Bool {
        if let generationError =
            error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = generationError {
            return true
        }
        // iOS 27 runtimes may surface the newer LanguageModelError
        // spelling; its identity is checked structurally so the 26.6
        // SDK still compiles this file.
        return String(describing: error)
            .localizedCaseInsensitiveContains("context")
            && String(describing: error)
                .localizedCaseInsensitiveContains("exceed")
    }

    /// Maps the generated mirror onto the typed suggestion, collecting
    /// violations for tokens outside the closed sets instead of
    /// dropping them — a hallucinated basis code/category is evidence
    /// of model failure, not silent data loss.
    private static func map(
        _ generated: FMEquipmentIdentitySuggestion,
        onViolation: (EquipmentIdentityAIViolation) -> Void
    ) -> EquipmentIdentitySuggestion {
        var basisCodes: [EquipmentIdentityBasisCode] = []
        for raw in generated.basisCodes {
            if let code = EquipmentIdentityBasisCode(rawValue: raw) {
                basisCodes.append(code)
            } else {
                onViolation(.unknownBasisCode)
            }
        }
        var category: EquipmentIdentityCategory?
        if let raw = generated.category {
            if let parsed = EquipmentIdentityCategory(rawValue: raw) {
                category = parsed
            } else {
                onViolation(.unknownCategory)
            }
        }
        return EquipmentIdentitySuggestion(
            manufacturer: normalizedOrNil(generated.manufacturer),
            model: normalizedOrNil(generated.model),
            serialOrAssetTag: normalizedOrNil(
                generated.serialOrAssetTag
            ),
            category: category,
            matchingCatalogSelectionKeys:
                generated.matchingCatalogSelectionKeys,
            evidenceLinks: generated.evidenceLinks,
            basisCodes: basisCodes,
            ambiguityReason: normalizedOrNil(generated.ambiguityReason),
            advisoryNote: normalizedOrNil(generated.advisoryNote),
            needsOperatorConfirmation:
                generated.needsOperatorConfirmation
        )
    }

    private static func normalizedOrNil(_ text: String?) -> String? {
        guard let trimmed = text?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
#endif
