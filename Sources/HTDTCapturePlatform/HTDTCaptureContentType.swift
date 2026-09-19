#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers

@available(iOS 17.0, macOS 14.0, *)
public extension UTType {
    static let htdtCapture = UTType(
        exportedAs: "com.hometheaterdigitaltwin.capture-bundle",
        conformingTo: .zip
    )
}

public enum HTDTCaptureFileType {
    public static let identifier =
        "com.hometheaterdigitaltwin.capture-bundle"
    public static let filenameExtension = "htdtcapture"
}
#endif
