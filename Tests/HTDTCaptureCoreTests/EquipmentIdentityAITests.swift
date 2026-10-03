import Foundation
import Testing
@testable import HTDTCaptureCore

// #270 multimodal equipment-identity assistant — deterministic core:
// bounded context, prompt composition, validator grounding, and the
// typed advisory outcome. The Foundation Models lane itself is
// availability-gated and never exercised here (Simulator/ineligible
// devices report `.unavailable`), so every test runs on the
// deterministic layer that wraps it.

private func aiTestEntry(
    id: String,
    version: String = "1.0.0",
    hash: String = "ab",
    manufacturer: String? = "Example Audio",
    model: String? = "Monitor X",
    userLabel: String? = nil
) throws -> HTDTEquipmentCatalogEntry {
    try HTDTEquipmentCatalogEntry(
        definitionID: id,
        version: version,
        semanticSHA256: EvidenceSHA256(
            String(repeating: hash, count: 32)
        ),
        identityKind: .manufacturer,
        manufacturer: manufacturer,
        model: model,
        userLabel: userLabel
    )
}

private func aiTestResult(
    observations: [String],
    catalog: [HTDTEquipmentCatalogEntry] = []
) -> EquipmentLabelScanResult {
    let observed = observations.map {
        EquipmentLabelScanObservation(
            text: $0,
            basis: .ocr,
            confidence: 0.9
        )
    }
    return EquipmentLabelScanResult(
        algorithm: EquipmentLabelScanMatcher.algorithm,
        algorithmVersion: EquipmentLabelScanMatcher.algorithmVersion,
        evidenceRef: "path:evidence/frames/label.json",
        candidates: EquipmentLabelScanMatcher.candidates(
            from: observed,
            catalog: catalog
        ),
        rawObservations: EquipmentLabelScanMatcher.rawStrings(
            from: observed
        )
    )
}

@Test
func aiContextCapsObservationsAndFieldLengths() throws {
    let long = String(repeating: "S", count: 200)
    let observations = (0..<40).map { "OBS-\($0)" } + [long]
    let context = EquipmentIdentityAIContext(
        result: aiTestResult(observations: observations),
        catalog: [],
        catalogContentSHA256: nil,
        budget: .default
    )
    #expect(
        context.rawObservations.count
            == EquipmentIdentityAIBudget.default.maxObservations
    )
    #expect(
        context.rawObservations.allSatisfy {
            $0.count
                <= EquipmentIdentityAIBudget.default
                    .maxObservationLength
        }
    )
}

@Test
func aiContextCatalogSliceStaysBoundedAndRelevant() throws {
    let match = try aiTestEntry(
        id: "amp-1",
        manufacturer: "Example Audio",
        model: "Monitor X"
    )
    // Unrelated entries never enter the slice even though they exist.
    let filler = try (0..<20).map { i in
        try aiTestEntry(
            id: "unrelated-\(i)",
            hash: String(format: "%02x", i + 1),
            manufacturer: "Other Brand",
            model: "Zed-\(i)"
        )
    }
    let context = EquipmentIdentityAIContext(
        result: aiTestResult(
            observations: ["amp-1@1.0.0", "SN 7741-9912"],
            catalog: [match] + filler
        ),
        catalog: [match] + filler,
        catalogContentSHA256: "feedbeef",
        budget: .default
    )
    #expect(context.catalogSlice.count == 1)
    #expect(
        context.catalogSlice.first?.selectionKey == match.selectionKey
    )
    #expect(context.catalogContentSHA256 == "feedbeef")
    #expect(
        context.matcherAlgorithm == EquipmentLabelScanMatcher.algorithm
    )
}

@Test
func aiContextSliceHonorsReducedBudget() throws {
    let entries = try (0..<10).map { i in
        try aiTestEntry(
            id: "amp-\(i)",
            hash: String(format: "%02x", i + 16),
            manufacturer: "Example Audio",
            model: "Monitor X-\(i)"
        )
    }
    // All entries resolve via the QR definition-id observation.
    let context = EquipmentIdentityAIContext(
        result: aiTestResult(
            observations: entries.map { "\($0.definitionID)@1.0.0" },
            catalog: entries
        ),
        catalog: entries,
        catalogContentSHA256: nil,
        budget: .reduced
    )
    #expect(
        context.catalogSlice.count
            <= EquipmentIdentityAIBudget.reduced.maxCatalogEntries
    )
    #expect(
        context.rawObservations.count
            <= EquipmentIdentityAIBudget.reduced.maxObservations
    )
}

@Test
func aiPromptComposesBoundedBlocks() throws {
    let entry = try aiTestEntry(id: "amp-1")
    let context = EquipmentIdentityAIContext(
        result: aiTestResult(
            observations: ["amp-1@1.0.0"],
            catalog: [entry]
        ),
        catalog: [entry],
        catalogContentSHA256: nil,
        budget: .default
    )
    let prompt = EquipmentIdentityAIPrompt.prompt(for: context)
    #expect(prompt.contains("OBS:"))
    #expect(prompt.contains("MATCH:"))
    #expect(prompt.contains("CAT:"))
    #expect(prompt.contains("amp-1@1.0.0"))
    // ASCII heuristic: roughly one token per four characters.
    #expect(
        EquipmentIdentityAIPrompt.estimatedTokens("abcd") == 1
    )
    // CJK costs ~one token per scalar (issue guidance).
    #expect(
        EquipmentIdentityAIPrompt.estimatedTokens("機器") == 2
    )
    #expect(
        EquipmentIdentityAIPrompt.estimatedTokens("機器a") >= 1
    )
}

@Test
func aiValidatorAcceptsGroundedSuggestion() throws {
    let entry = try aiTestEntry(id: "amp-1")
    let context = EquipmentIdentityAIContext(
        result: aiTestResult(
            observations: [
                "Example Audio", "Monitor X", "SN 7741-9912",
            ],
            catalog: [entry]
        ),
        catalog: [entry],
        catalogContentSHA256: nil,
        budget: .default
    )
    let suggestion = EquipmentIdentitySuggestion(
        manufacturer: "Example Audio",
        model: "Monitor X",
        serialOrAssetTag: "SN 7741-9912",
        category: .speaker,
        matchingCatalogSelectionKeys: [entry.selectionKey],
        evidenceLinks: ["Example Audio", "Monitor X"],
        basisCodes: [.ocrStringMatch, .catalogRetrieval],
        advisoryNote: "Label matches catalog entry.",
        needsOperatorConfirmation: true
    )
    #expect(
        EquipmentIdentityAIValidator.violations(
            in: suggestion,
            context: context
        ).isEmpty
    )
}

@Test
func aiValidatorRejectsUngroundedAndForeignClaims() throws {
    let entry = try aiTestEntry(id: "amp-1")
    let other = try aiTestEntry(
        id: "other-9",
        hash: "cd",
        manufacturer: "Elsewhere",
        model: "Nothing X"
    )
    let context = EquipmentIdentityAIContext(
        result: aiTestResult(
            observations: ["Example Audio", "Monitor X"],
            catalog: [entry]
        ),
        catalog: [entry],
        catalogContentSHA256: nil,
        budget: .default
    )
    let suggestion = EquipmentIdentitySuggestion(
        manufacturer: "Invented Brand",
        model: "Imaginary 9000",
        serialOrAssetTag: "SN-NOT-THERE",
        category: .speaker,
        matchingCatalogSelectionKeys: [other.selectionKey],
        evidenceLinks: ["Example Audio", "not an observation"],
        basisCodes: [.ocrStringMatch],
        needsOperatorConfirmation: true
    )
    let violations = EquipmentIdentityAIValidator.violations(
        in: suggestion,
        context: context
    )
    #expect(violations.contains(.ungroundedManufacturer))
    #expect(violations.contains(.ungroundedModel))
    #expect(violations.contains(.ungroundedSerial))
    #expect(violations.contains(.unknownCatalogKey))
    #expect(violations.contains(.unknownEvidenceLink))
}

@Test
func aiValidatorRejectsAuthorityClaimAndOversizedNote() throws {
    let context = EquipmentIdentityAIContext(
        result: aiTestResult(observations: ["Monitor X"]),
        catalog: [],
        catalogContentSHA256: nil,
        budget: .default
    )
    let suggestion = EquipmentIdentitySuggestion(
        model: "Monitor X",
        advisoryNote: String(repeating: "n", count: 400),
        needsOperatorConfirmation: false
    )
    let violations = EquipmentIdentityAIValidator.violations(
        in: suggestion,
        context: context
    )
    #expect(violations.contains(.confirmationNotRequired))
    #expect(violations.contains(.oversizedAdvisoryNote))
}

@Test
func aiVacuousSuggestionIsCleanAbstention() {
    #expect(EquipmentIdentitySuggestion().isVacuous)
    #expect(
        !EquipmentIdentitySuggestion(model: "M").isVacuous
    )
    #expect(
        !EquipmentIdentitySuggestion(
            matchingCatalogSelectionKeys: ["k"]
        ).isVacuous
    )
}

@Test
func aiAdvisoryNeverAltersDeterministicResult() throws {
    // The advisory rides alongside the scan result; constructing a
    // result with an advisory changes nothing about the deterministic
    // lanes it mirrors.
    let result = aiTestResult(observations: ["Monitor X"])
    let advisory = EquipmentIdentityAIResult(
        status: .validatorRejected,
        violations: [.ungroundedModel],
        provenance: EquipmentIdentityAIProvenance(
            promptRevision: EquipmentIdentityAIPrompt.promptRevision,
            modelAvailability: "unavailable(deviceNotEligible)",
            osVersion: "test",
            localeIdentifier: "en_US",
            supportedLocale: nil,
            estimatedPromptTokens: 0,
            catalogContentSHA256: nil,
            matcherAlgorithm: result.algorithm,
            matcherVersion: result.algorithmVersion,
            attempts: 0
        )
    )
    let decorated = EquipmentLabelScanResult(
        algorithm: result.algorithm,
        algorithmVersion: result.algorithmVersion,
        evidenceRef: result.evidenceRef,
        candidates: result.candidates,
        rawObservations: result.rawObservations,
        aiAdvisory: advisory
    )
    #expect(decorated.candidates == result.candidates)
    #expect(decorated.rawObservations == result.rawObservations)
    #expect(decorated.aiAdvisory?.status == .validatorRejected)
    // Default init stays advisory-free.
    #expect(result.aiAdvisory == nil)
}
