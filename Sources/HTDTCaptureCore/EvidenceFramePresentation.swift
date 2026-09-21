import Foundation

/// Why a persisted evidence frame exists (#255 selector). Set by the
/// host at capture time; kept as a stable token, not localized text.
public enum EvidenceFrameRetentionKind: String, Codable, Sendable {
    /// Manually captured "evidence frame" during scanning.
    case manualScan = "manual_scan"
    /// Frame produced by an annotation placement capture.
    case annotationPlacement = "annotation_placement"
    /// Frame produced by a speaker-heading capture.
    case speakerHeading = "speaker_heading"
    /// Frame produced by an equipment-identity photo capture (#239).
    case equipmentIdentity = "equipment_identity"
    /// Retention reason is not recorded for this frame.
    case unknown
}

/// Presentation data for one persisted evidence frame — the exact
/// canonical `path:` ref stays the authority; the UI layers thumbnails
/// and metadata over it (#255).
public struct EvidenceFramePresentation: Sendable, Equatable, Identifiable {
    /// Canonical evidence ref (e.g. `path:evidence/frames/<id>.json`).
    public let reference: String
    /// Frame UUID parsed from the descriptor filename, when readable.
    public let frameID: UUID?
    /// UTC timestamp of the AR session capture, when the descriptor
    /// could be decoded.
    public let sessionTimestampSeconds: Double?
    /// Whether a scene-depth payload is attached to the frame.
    public let hasDepth: Bool
    /// Whether a derived preview image exists on disk.
    public let hasPreview: Bool
    /// App-local URL of the `.preview.heic` image, when present.
    public let previewFileURL: URL?
    /// Camera world position at capture (descriptor `worldFromCamera`
    /// translation), used to distinguish viewpoints in the picker.
    public let cameraPositionWorld: Float3?
    /// Host-supplied retention reason.
    public var retentionKind: EvidenceFrameRetentionKind

    public var id: String { reference }

    public init(
        reference: String,
        frameID: UUID?,
        sessionTimestampSeconds: Double?,
        hasDepth: Bool,
        hasPreview: Bool,
        previewFileURL: URL?,
        cameraPositionWorld: Float3?,
        retentionKind: EvidenceFrameRetentionKind = .unknown
    ) {
        self.reference = reference
        self.frameID = frameID
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.hasDepth = hasDepth
        self.hasPreview = hasPreview
        self.previewFileURL = previewFileURL
        self.cameraPositionWorld = cameraPositionWorld
        self.retentionKind = retentionKind
    }
}

/// Loads `EvidenceFramePresentation`s for a working-set root (#255).
/// Pure file reads under `rootDirectory`; a frame whose descriptor or
/// preview is missing degrades to metadata-only rather than dropping
/// the ref — the canonical reference is still selectable.
public enum EvidenceFramePresentationLoader {
    /// Loads presentations for each `path:` ref in `references` in
    /// order; non-`path:` refs and unreadable descriptors produce a
    /// metadata-only entry (frameID/timestamps nil).
    public static func load(
        references: [String],
        workingSetRoot: URL,
        retentionKinds: [String: EvidenceFrameRetentionKind] = [:]
    ) -> [EvidenceFramePresentation] {
        references.map { reference in
            var presentation = base(
                reference: reference,
                workingSetRoot: workingSetRoot
            )
            presentation.retentionKind =
                retentionKinds[reference] ?? .unknown
            return presentation
        }
    }

    private static func base(
        reference: String,
        workingSetRoot: URL
    ) -> EvidenceFramePresentation {
        guard let relativePath = Self.descriptorPath(
            for: reference
        ) else {
            return EvidenceFramePresentation(
                reference: reference,
                frameID: nil,
                sessionTimestampSeconds: nil,
                hasDepth: false,
                hasPreview: false,
                previewFileURL: nil,
                cameraPositionWorld: nil
            )
        }

        let descriptorURL = workingSetRoot.appendingPathComponent(
            relativePath,
            isDirectory: false
        )
        let descriptor = try? JSONDecoder().decode(
            FrameEvidenceDescriptor.self,
            from: Data(contentsOf: descriptorURL)
        )

        let stem = URL(fileURLWithPath: relativePath)
            .deletingPathExtension()
            .lastPathComponent
        let previewURL = workingSetRoot.appendingPathComponent(
            "evidence/frames/" + stem + ".preview.heic",
            isDirectory: false
        )
        let hasPreview = FileManager.default.fileExists(
            atPath: previewURL.path
        )

        return EvidenceFramePresentation(
            reference: reference,
            frameID: UUID(uuidString: stem),
            sessionTimestampSeconds:
                descriptor?.sessionTimestampSeconds,
            hasDepth: descriptor?.depthStatus == .capturedDiscrete
                || descriptor?.depthStatus == .capturedSmoothed,
            hasPreview: hasPreview,
            previewFileURL: hasPreview ? previewURL : nil,
            cameraPositionWorld:
                descriptor?.worldFromCamera.translationWorld
        )
    }

    /// Maps a canonical `path:` evidence ref to its relative descriptor
    /// path inside the working set, or nil for non-frame refs.
    public static func descriptorPath(for reference: String) -> String? {
        guard reference.hasPrefix("path:evidence/frames/") else {
            return nil
        }
        let path = String(reference.dropFirst(5))
        guard path.hasSuffix(".json") else {
            return nil
        }
        return path
    }
}
