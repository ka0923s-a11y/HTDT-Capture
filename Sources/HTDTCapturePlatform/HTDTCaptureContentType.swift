#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers

@available(iOS 17.0, macOS 14.0, *)
public extension UTType {
    static let htdtCapture = UTType(
        exportedAs: "com.hometheaterdigitaltwin.capture-bundle",
        conformingTo: .zip
    )

    /// Capture Library portability container (issue #378): a
    /// versioned package of `.htdtcapture` archives plus filtered
    /// app-local metadata and handoff receipts.
    static let htdtCaptureLibrary = UTType(
        exportedAs: "com.hometheaterdigitaltwin.capture-library",
        conformingTo: .zip
    )

    /// HTDT mission package (issue #457): the `.htdtmission`
    /// envelope/document the capture imports as a mission record.
    /// Imported (not exported) — the mission issuer owns the type.
    static let htdtMission = UTType(
        importedAs: "com.hometheaterdigitaltwin.capture-mission",
        conformingTo: .json
    )
}

public enum HTDTCaptureFileType {
    public static let identifier =
        "com.hometheaterdigitaltwin.capture-bundle"
    public static let filenameExtension = "htdtcapture"
}

public enum HTDTCaptureLibraryFileType {
    public static let identifier =
        "com.hometheaterdigitaltwin.capture-library"
    public static let filenameExtension = "htdtcapturelibrary"
}
#endif
