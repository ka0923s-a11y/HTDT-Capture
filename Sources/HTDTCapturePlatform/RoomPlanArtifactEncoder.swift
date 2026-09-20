import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(RoomPlan)
import RoomPlan

@available(iOS 17.0, *)
public enum RoomPlanArtifactEncoder {
    private static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // CapturedRoomData is an opaque Apple payload and can contain
        // exceptional IEEE-754 values in partially observed geometry.
        // JSONEncoder throws on NaN/Infinity by default, which incorrectly
        // turned an otherwise usable RoomPlan stop result into a terminal
        // "persistence" failure. Preserve those values deterministically.
        encoder.nonConformingFloatEncodingStrategy =
            .convertToString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
        return encoder
    }

    public static func encodeRaw(_ raw: CapturedRoomData) throws -> Data {
        try makeJSONEncoder().encode(raw)
    }

    public static func encodeProcessed(_ room: CapturedRoom) throws -> Data {
        try makeJSONEncoder().encode(room)
    }

    public static func diagnosticToken(_ error: Error) -> String {
        if let encodingError = error as? EncodingError {
            switch encodingError {
            case .invalidValue:
                return "encoding_invalid_value"
            @unknown default:
                return "encoding_failed"
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return "encoding_cocoa:" + String(nsError.code)
        }
        return "encoding_failed"
    }
}
#endif
