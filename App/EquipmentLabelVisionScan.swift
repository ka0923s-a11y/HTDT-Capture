import CoreVideo
import Foundation
import Vision
import HTDTCaptureCore

/// Label-scan recognizer (#345): runs Vision text recognition and
/// barcode/QR detection on a retained camera pixel buffer and returns
/// observations for `EquipmentLabelScanMatcher`. Pure assist —
/// the result only ever produces operator-confirmed suggestions;
/// nothing it returns is committed anywhere.
enum EquipmentLabelVisionScan {
    /// Runs OCR + barcode/QR detection on `pixelBuffer`. Returns the
    /// distinct observations with their provenance; an empty result
    /// (clean frame, unreadable label) is not an error — the matcher
    /// produces an empty candidate list and the operator falls back
    /// to manual entry.
    static func recognize(
        _ pixelBuffer: CVPixelBuffer
    ) async throws -> [EquipmentLabelScanObservation] {
        try await Task.detached(priority: .userInitiated) {
            var observations: [EquipmentLabelScanObservation] = []

            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = false
            // Serial/model strings stay verbatim — language
            // correction would rewrite them into dictionary words.
            textRequest.recognitionLanguages = ["en"]
            textRequest.minimumTextHeight = 0.01

            let barcodeRequest = VNDetectBarcodesRequest()
            barcodeRequest.symbologies = [
                .qr, .qrMicro, .aztec, .dataMatrix,
                .code39, .code39Checksum, .code39FullASCII,
                .code93, .code128,
                .ean8, .ean13, .upce,
                .pdf417, .itf14, .interleaved2of5,
            ]

            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                options: [:]
            )
            try handler.perform([textRequest, barcodeRequest])

            for observation in
                textRequest.results ?? []
            {
                guard let candidate = observation
                    .topCandidates(1)
                    .first
                else {
                    continue
                }
                let text = candidate.string
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                if !text.isEmpty {
                    observations.append(
                        EquipmentLabelScanObservation(
                            text: text,
                            basis: .ocr,
                            confidence: candidate.confidence
                        )
                    )
                }
            }

            for barcode in barcodeRequest.results ?? [] {
                guard let payload = barcode.payloadStringValue,
                      !payload.isEmpty
                else {
                    continue
                }
                let basis: EquipmentLabelScanBasis =
                    barcode.symbology == .qr
                        || barcode.symbology == .qrMicro
                        ? .qrCode
                        : .barcode
                observations.append(
                    EquipmentLabelScanObservation(
                        text: payload,
                        basis: basis,
                        confidence: 1.0
                    )
                )
            }

            return observations
        }.value
    }
}
