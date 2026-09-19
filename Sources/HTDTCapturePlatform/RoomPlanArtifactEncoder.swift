import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(RoomPlan)
import RoomPlan

@available(iOS 17.0, *)
public enum RoomPlanArtifactEncoder {
    public static func encodeRaw(_ raw: CapturedRoomData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(raw)
    }

    public static func encodeProcessed(_ room: CapturedRoom) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(room)
    }
}
#endif
