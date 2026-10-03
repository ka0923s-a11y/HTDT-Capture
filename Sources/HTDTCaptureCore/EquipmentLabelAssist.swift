import Foundation

public enum EquipmentLabelScanError: Error, Sendable {
    /// The host has no label-scan capability (e.g. no camera/vision
    /// surface); the UI hides or disables the control.
    case scanUnavailable
}

/// How one raw string was observed on the scanned label (legacy bolph71656-ai/HTDT-Capture#345):
/// OCR text, a barcode payload, or a QR-code payload.
public enum EquipmentLabelScanBasis:
    String,
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    case ocr
    case barcode
    case qrCode = "qr_code"
}

/// One string the recognizer returned, with its provenance.
public struct EquipmentLabelScanObservation:
    Sendable,
    Equatable,
    Hashable
{
    public let text: String
    public let basis: EquipmentLabelScanBasis
    /// Recognizer confidence 0…1; barcode/QR payloads report 1.0.
    public let confidence: Float

    public init(
        text: String,
        basis: EquipmentLabelScanBasis,
        confidence: Float
    ) {
        self.text = text
        self.basis = basis
        self.confidence = confidence
    }
}

/// A SUGGESTED identity for the scanned unit (legacy bolph71656-ai/HTDT-Capture#345). Candidates are
/// never auto-committed: the operator must pick one explicitly (or
/// dismiss the sheet), and the serial field remains editable because a
/// printed serial is a lookup hint, not proof of identity.
public struct EquipmentLabelScanCandidate:
    Sendable,
    Equatable,
    Hashable
{
    public let manufacturer: String?
    public let model: String?
    public let serialOrAssetTag: String?
    /// `selectionKey` of the catalog entry this candidate matches, when
    /// the suggestion resolves inside the imported catalog.
    public let catalogSelectionKey: String?
    /// Aggregate confidence 0…1 (heuristic — matching is suggestion,
    /// not determination).
    public let confidence: Float
    /// Which observation channels produced this candidate.
    public let bases: [EquipmentLabelScanBasis]
    /// The exact observed strings the candidate was derived from —
    /// retained so the UI shows raw evidence behind each suggestion.
    public let rawStrings: [String]

    public init(
        manufacturer: String? = nil,
        model: String? = nil,
        serialOrAssetTag: String? = nil,
        catalogSelectionKey: String? = nil,
        confidence: Float,
        bases: [EquipmentLabelScanBasis],
        rawStrings: [String]
    ) {
        self.manufacturer = manufacturer
        self.model = model
        self.serialOrAssetTag = serialOrAssetTag
        self.catalogSelectionKey = catalogSelectionKey
        self.confidence = confidence
        self.bases = bases
        self.rawStrings = rawStrings
    }
}

/// The complete scan result handed to the confirmation sheet (legacy bolph71656-ai/HTDT-Capture#345).
/// Nothing in the result has been committed anywhere; the sheet maps a
/// confirmed candidate onto the form's equipment/serial fields.
public struct EquipmentLabelScanResult: Sendable, Equatable {
    /// Stable algorithm identifier retained in identity-record
    /// provenance.
    public let algorithm: String
    /// Algorithm version, bumped whenever the matcher changes.
    public let algorithmVersion: String
    /// Evidence ref (`path:...`) of the persisted source frame the
    /// scan ran on — the image stays linked to the suggestion.
    public let evidenceRef: String
    /// Advisory usability of the exact source image (legacy bolph71656-ai/HTDT-Capture#407). Deliberately
    /// distinct from `confidence` (recognition), catalog-match
    /// confidence, and operator confirmation: a blurry but perfectly
    /// recognized label keeps image quality and match confidence
    /// separate.
    public let imageQuality: EvidenceImageQualityAssessment?
    public let candidates: [EquipmentLabelScanCandidate]
    /// Every distinct observed string, for the sheet's raw-text view.
    public let rawObservations: [String]
    /// Optional Foundation Models advisory lane outcome (#270). Always
    /// nil unless the experimental flag ran the bounded pass; advisory
    /// only — it never modifies `candidates`/`rawObservations`, and a
    /// suggestion can never be applied without the operator picking a
    /// deterministic candidate as usual.
    public let aiAdvisory: EquipmentIdentityAIResult?

    public init(
        algorithm: String,
        algorithmVersion: String,
        evidenceRef: String,
        candidates: [EquipmentLabelScanCandidate],
        rawObservations: [String],
        imageQuality: EvidenceImageQualityAssessment? = nil,
        aiAdvisory: EquipmentIdentityAIResult? = nil
    ) {
        self.algorithm = algorithm
        self.algorithmVersion = algorithmVersion
        self.evidenceRef = evidenceRef
        self.candidates = candidates
        self.rawObservations = rawObservations
        self.imageQuality = imageQuality
        self.aiAdvisory = aiAdvisory
    }

    /// True when the operator genuinely has to choose — zero or more
    /// than one distinct candidate. A single high-confidence match
    /// still requires the tap; this flag only means the sheet shows a
    /// real ambiguity.
    public var isAmbiguous: Bool {
        candidates.count != 1
    }
}

/// Provenance recorded on `EquipmentIdentityRecord.label_scan` when a
/// suggestion was confirmed (legacy bolph71656-ai/HTDT-Capture#345): the algorithm+version that produced
/// it and the persisted source image. Its presence marks the record's
/// fields as machine-suggested-then-operator-confirmed, distinct from
/// fully manually attested fields.
public struct EquipmentLabelScanProvenance:
    Codable,
    Sendable,
    Equatable,
    Hashable
{
    public let algorithm: String
    public let algorithmVersion: String
    /// `path:` ref of the persisted source frame.
    public let evidenceRef: String
    /// Raw strings the confirmed candidate was derived from.
    public let matchedRawStrings: [String]

    public init(
        algorithm: String,
        algorithmVersion: String,
        evidenceRef: String,
        matchedRawStrings: [String]
    ) throws {
        let normalizedAlgorithm = SchemaOwnedText.nfc(algorithm)
        let normalizedVersion = SchemaOwnedText.nfc(algorithmVersion)
        let normalizedRef = SchemaOwnedText.nfc(evidenceRef)
        guard !normalizedAlgorithm.isEmpty,
              !normalizedVersion.isEmpty,
              normalizedRef.hasPrefix("path:")
        else {
            throw ExternalAuthorityDependencyError.emptyField
        }
        self.algorithm = normalizedAlgorithm
        self.algorithmVersion = normalizedVersion
        self.evidenceRef = normalizedRef
        self.matchedRawStrings = matchedRawStrings
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case algorithmVersion = "algorithm_version"
        case evidenceRef = "evidence_ref"
        case matchedRawStrings = "matched_raw_strings"
    }
}

/// Suggestion matcher (legacy bolph71656-ai/HTDT-Capture#345) — pure and deterministic so the same
/// observations always produce the same candidates and the matcher is
/// fully unit-testable without Vision.
///
/// Strategy: normalize every observed string to uppercase
/// alphanumeric, then
/// - barcode/QR payloads that equal a catalog `definition_id` or a
///   serialized `id@version` pair produce high-confidence catalog
///   candidates;
/// - observed strings equal to (or containing) a catalog `model` or
///   `definition_id` produce catalog candidates;
/// - observed strings equal to a catalog `manufacturer` mark the
///   manufacturer guess;
/// - remaining token-shaped strings with at least one digit are
///   offered as serial candidates;
/// - two-part strings like `MAKE MODEL` observed together pick the
///   catalog entry covering both tokens when unambiguous.
public enum EquipmentLabelScanMatcher {
    public static let algorithm = "vision-ocr-barcode"
    public static let algorithmVersion = "1.0.0"

    public static func normalize(_ text: String) -> String {
        let scalars = text.uppercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Everything the raw observations contained, deduplicated and
    /// sorted — the `rawObservations` payload of the result.
    public static func rawStrings(
        from observations: [EquipmentLabelScanObservation]
    ) -> [String] {
        Array(Set(observations.map(\.text))).sorted()
    }

    /// Suggested candidates for `observations`, ranked by confidence
    /// descending. An empty scan or no extractable fields yields `[]`
    /// — the sheet still opens so the operator sees "no suggestion /
    /// enter manually".
    public static func candidates(
        from observations: [EquipmentLabelScanObservation],
        catalog: [HTDTEquipmentCatalogEntry]
    ) -> [EquipmentLabelScanCandidate] {
        var byKey:
            [String: EquipmentLabelScanCandidate] = [:]

        func merge(
            _ candidate: EquipmentLabelScanCandidate
        ) {
            let key =
                (candidate.catalogSelectionKey ?? "-")
                + "|" + (candidate.manufacturer ?? "-")
                + "|" + (candidate.model ?? "-")
                + "|" + (candidate.serialOrAssetTag ?? "-")
            if let existing = byKey[key] {
                let mergedBases = Array(
                    Set(existing.bases + candidate.bases)
                ).sorted { $0.rawValue < $1.rawValue }
                let mergedRaw = Array(
                    Set(existing.rawStrings + candidate.rawStrings)
                ).sorted()
                byKey[key] = EquipmentLabelScanCandidate(
                    manufacturer: candidate.manufacturer
                        ?? existing.manufacturer,
                    model: candidate.model ?? existing.model,
                    serialOrAssetTag: candidate.serialOrAssetTag
                        ?? existing.serialOrAssetTag,
                    catalogSelectionKey:
                        candidate.catalogSelectionKey
                            ?? existing.catalogSelectionKey,
                    confidence: max(
                        existing.confidence,
                        candidate.confidence
                    ),
                    bases: mergedBases,
                    rawStrings: mergedRaw
                )
            } else {
                byKey[key] = candidate
            }
        }

        let normalizedObservations: [(
            observation: EquipmentLabelScanObservation,
            normalized: String
        )] = observations.compactMap { observation in
            let normalized = normalize(observation.text)
            return normalized.isEmpty
                ? nil
                : (observation, normalized)
        }
        let normalizedSet = Set(normalizedObservations.map(\.normalized))

        // Catalog-definition match: an observed string equal to a
        // definition ID, to `ID@VERSION`, or containing the model.
        for entry in catalog {
            var bases: Set<EquipmentLabelScanBasis> = []
            var raw: Set<String> = []
            var best: Float = 0
            let normalizedID = normalize(entry.definitionID)
            let normalizedModel = entry.model.map(normalize)
            let normalizedManufacturer = entry.manufacturer.map(
                normalize
            )
            for pair in normalizedObservations {
                let text = pair.normalized
                let observation = pair.observation
                var hit: Float = 0
                if text == normalizedID
                    || text == normalizedID
                        + normalize(entry.version)
                    || text
                        == normalize(
                            entry.definitionID + "@" + entry.version
                        )
                {
                    hit = observation.basis == .ocr ? 0.8 : 0.95
                } else if let normalizedModel,
                          !normalizedModel.isEmpty,
                          text == normalizedModel
                {
                    hit = observation.basis == .ocr ? 0.7 : 0.9
                } else if let normalizedModel,
                          normalizedModel.count >= 3,
                          text.contains(normalizedModel)
                {
                    hit = 0.6
                }
                if hit > 0 {
                    bases.insert(observation.basis)
                    raw.insert(observation.text)
                    best = max(best, hit * observation.confidence)
                }
            }
            if best > 0 {
                merge(
                    EquipmentLabelScanCandidate(
                        manufacturer: entry.manufacturer,
                        model: entry.model,
                        catalogSelectionKey: entry.selectionKey,
                        confidence: min(best, 1),
                        bases: bases.sorted { $0.rawValue < $1.rawValue },
                        rawStrings: raw.sorted()
                    )
                )
            }
            _ = normalizedManufacturer
        }

        // Manufacturer-only guesses: observed string equals a catalog
        // manufacturer name without matching a model.
        for entry in catalog {
            guard let manufacturer = entry.manufacturer else {
                continue
            }
            let normalizedManufacturer = normalize(manufacturer)
            guard !normalizedManufacturer.isEmpty,
                  normalizedSet.contains(normalizedManufacturer)
            else {
                continue
            }
            let observationsHit = normalizedObservations.filter {
                $0.normalized == normalizedManufacturer
            }
            merge(
                EquipmentLabelScanCandidate(
                    manufacturer: manufacturer,
                    confidence: 0.4 * (observationsHit.first?
                        .observation.confidence ?? 1),
                    bases: observationsHit.map(\.observation.basis),
                    rawStrings: observationsHit.map(
                        \.observation.text
                    ).sorted()
                )
            )
        }

        // Serial candidates: token-shaped strings containing at least
        // one digit that did not resolve to a catalog identity.
        for pair in normalizedObservations {
            let text = pair.normalized
            guard text.count >= 6,
                  text.contains(
                      where: { $0.isNumber }
                  )
            else {
                continue
            }
            let resolvesToCatalog = catalog.contains { entry in
                text == normalize(entry.definitionID)
                    || (entry.model.map(normalize) == text)
            }
            if resolvesToCatalog { continue }
            merge(
                EquipmentLabelScanCandidate(
                    serialOrAssetTag: pair.observation.text,
                    confidence: 0.35
                        * pair.observation.confidence,
                    bases: [pair.observation.basis],
                    rawStrings: [pair.observation.text]
                )
            )
        }

        return byKey.values.sorted {
            $0.confidence > $1.confidence
        }
    }
}
