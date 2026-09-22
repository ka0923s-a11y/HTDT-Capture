import Foundation
import SwiftUI
import HTDTCaptureCore
#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif
#if canImport(UIKit)
import UIKit
#endif

/// What the host reports about a finalized capture for the derived
/// export sheets (issue #306): which geometry sources are available
/// and which evidence previews may be offered for explicit selection.
public struct DerivedExportInfo: Sendable, Equatable {
    /// `roomplan/captured-room.json` is declared, present, and
    /// decodable — enables the RoomPlan-derived formats.
    public let roomPlanProcessedAvailable: Bool
    /// USDZ is RoomPlan-native and only produced on iOS.
    public let usdzAvailable: Bool
    /// `mesh/anchors.json` plus geometry payloads exist.
    public let arMeshAvailable: Bool
    public let arMeshAnchorCount: Int
    /// Evidence frames carrying a preview payload — the only frames
    /// the report sheet may offer for embedding.
    public let evidenceOptions: [SurveyReportEvidenceOption]
    /// Set when the capture's finalized bundle could not be resolved
    /// at all.
    public let failureReason: String?

    public init(
        roomPlanProcessedAvailable: Bool,
        usdzAvailable: Bool,
        arMeshAvailable: Bool,
        arMeshAnchorCount: Int,
        evidenceOptions: [SurveyReportEvidenceOption],
        failureReason: String? = nil
    ) {
        self.roomPlanProcessedAvailable = roomPlanProcessedAvailable
        self.usdzAvailable = usdzAvailable
        self.arMeshAvailable = arMeshAvailable
        self.arMeshAnchorCount = arMeshAnchorCount
        self.evidenceOptions = evidenceOptions
        self.failureReason = failureReason
    }
}

/// What the operator chose in the derived-3D sheet.
public struct Derived3DExportSelection: Sendable, Equatable {
    public var format: DerivedExportFormat
    public var source: DerivedExportSourceKind

    public init(
        format: DerivedExportFormat,
        source: DerivedExportSourceKind
    ) {
        self.format = format
        self.source = source
    }
}

/// What the operator chose in the survey-report sheet.
public struct SurveyReportSelection: Sendable, Equatable {
    public var language: SurveyReportLanguage
    /// `SurveyReportEvidenceOption.id` values — only these frames are
    /// embedded. Empty means no camera imagery at all.
    public var evidenceFrameIDs: Set<String>

    public init(
        language: SurveyReportLanguage,
        evidenceFrameIDs: Set<String> = []
    ) {
        self.language = language
        self.evidenceFrameIDs = evidenceFrameIDs
    }
}

/// The outcome of a derived export: produced files on success, a
/// user-readable reason on failure.
public struct DerivedExportOutcome: Sendable, Equatable {
    public let files: [URL]
    public let error: String?

    public init(files: [URL], error: String?) {
        self.files = files
        self.error = error
    }
}

/// Converts a retained HEIC preview into a bounded JPEG for the survey
/// report. Uses ImageIO so it works on iOS and macOS; returns nil when
/// the file cannot be decoded — the caller drops the frame rather than
/// failing the report.
public enum SurveyReportImageConverter {
    public static func jpegData(
        from url: URL,
        maxPixelSize: Int = 960,
        quality: Double = 0.75
    ) -> Data? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            nil
        )
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        )
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        )
        else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [
                kCGImageDestinationLossyCompressionQuality: quality
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
        #else
        return nil
        #endif
    }
}

/// The target of a derived-export sheet — a validated finalized
/// capture revision (the active adoption or a library record).
public struct DerivedExportTarget: Identifiable, Sendable, Equatable {
    public let revisionID: CaptureRevisionID
    public let displayName: String?

    public init(
        revisionID: CaptureRevisionID,
        displayName: String? = nil
    ) {
        self.revisionID = revisionID
        self.displayName = displayName
    }

    public var id: String { revisionID.description }
}

// MARK: - Derived 3D sheet

/// Derived 3D model export (issue #306). The sheet states up front
/// that the output is derived convenience geometry — not canonical
/// evidence — and that no camera imagery or depth is included, so the
/// privacy difference from the full `.htdtcapture` bundle is explicit.
public struct Derived3DExportSheet: View {
    public let target: DerivedExportTarget
    public let actions: CaptureRootActions

    @State private var info: DerivedExportInfo?
    @State private var source: DerivedExportSourceKind =
        .roomPlanProcessed
    @State private var format: DerivedExportFormat = .glb
    @State private var isExporting = false
    @State private var outcome: DerivedExportOutcome?
    @Environment(\.dismiss) private var dismiss

    public init(
        target: DerivedExportTarget,
        actions: CaptureRootActions
    ) {
        self.target = target
        self.actions = actions
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Derived output — not canonical capture evidence. The .htdtcapture bundle remains the evidence record; this file is a convenience export for external 3D tools."
                    )
                    Text(
                        "Contains geometry only — no camera imagery, depth frames, annotations, or measurements are embedded."
                    )
                    .foregroundStyle(.secondary)
                } header: {
                    Text(
                        "What this is"
                    )
                }

                Section("Geometry source") {
                    sourceRow(
                        .roomPlanProcessed,
                        title:
                            "RoomPlan surfaces & objects",
                        detail:
                            "Bounding boxes synthesized from the processed RoomPlan model. Not measured surface geometry."
                    )
                    sourceRow(
                        .arMeshAnchors,
                        title: "ARKit scanned mesh",
                        detail:
                            "The recorded scene mesh merged into world space."
                    )
                }

                Section("Format") {
                    ForEach(
                        formatsForSource,
                        id: \.self
                    ) { candidate in
                        formatRow(candidate)
                    }
                }

                if let failure = info?.failureReason {
                    Section {
                        Text(failure)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        isExporting = true
                        Task {
                            outcome =
                                await actions.exportDerived3D(
                                    target.revisionID,
                                    Derived3DExportSelection(
                                        format: format,
                                        source: source
                                    )
                                )
                            isExporting = false
                        }
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Text("Export 3D model")
                        }
                    }
                    .disabled(
                        isExporting
                            || !sourceAvailable
                            || info == nil
                    )
                    Text(
                        "A provenance record (.provenance.json) is written next to the model: it binds the file to this exact capture revision and bundle digest, the coordinate space, and the transform and units applied."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let outcome {
                    if let error = outcome.error {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    } else if !outcome.files.isEmpty {
                        Section("Exported files") {
                            ForEach(
                                outcome.files,
                                id: \.self
                            ) { file in
                                ShareLink(item: file) {
                                    Label(
                                        file.lastPathComponent,
                                        systemImage:
                                            "square.and.arrow.up"
                                    )
                                }
                            }
                            Text(
                                "Provenance fields are embedded in the file itself (comments / glTF extras) and in the sidecar record."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Derived 3D export")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            info = await actions.derivedExportInfo(
                target.revisionID
            )
            if let info {
                if !info.roomPlanProcessedAvailable,
                   info.arMeshAvailable
                {
                    source = .arMeshAnchors
                }
                if !source.supportedFormats.contains(format) {
                    format = source.supportedFormats[0]
                }
            }
        }
        .onChange(of: source) {
            if !source.supportedFormats.contains(format) {
                format = source.supportedFormats[0]
            }
        }
    }

    private var formatsForSource: [DerivedExportFormat] {
        source.supportedFormats.filter {
            $0 != .usdz || info?.usdzAvailable == true
        }
    }

    private var sourceAvailable: Bool {
        guard let info else { return false }
        switch source {
        case .roomPlanProcessed:
            return info.roomPlanProcessedAvailable
        case .arMeshAnchors:
            return info.arMeshAvailable
        }
    }

    @ViewBuilder
    private func formatRow(
        _ candidate: DerivedExportFormat
    ) -> some View {
        Button {
            format = candidate
        } label: {
            HStack {
                Text(formatLabel(candidate))
                    .foregroundStyle(.primary)
                Spacer()
                if candidate == format {
                    Image(
                        systemName: "checkmark.circle.fill"
                    )
                    .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isAvailable(
        _ kind: DerivedExportSourceKind
    ) -> Bool {
        switch kind {
        case .roomPlanProcessed:
            return info?.roomPlanProcessedAvailable ?? false
        case .arMeshAnchors:
            return info?.arMeshAvailable ?? false
        }
    }

    @ViewBuilder
    private func sourceRow(
        _ kind: DerivedExportSourceKind,
        title: String,
        detail: String
    ) -> some View {
        let available = isAvailable(kind)
        Button {
            source = kind
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(
                            available ? .primary : .secondary
                        )
                    Text(
                        available
                            ? detail
                            : String(localized: "Not recorded in this capture")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if source == kind {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    private func formatLabel(
        _ format: DerivedExportFormat
    ) -> String {
        switch format {
        case .usdz:
            "USDZ (RoomPlan parametric)"
        case .glb:
            "GLB (glTF binary)"
        case .obj:
            "OBJ (Wavefront)"
        case .ply:
            "PLY (ASCII)"
        }
    }
}

// MARK: - Survey report sheet

/// Field-survey report export (issue #318): language choice plus the
/// explicit per-frame preview opt-in — nothing camera-derived is
/// embedded unless the operator selects it here.
public struct SurveyReportExportSheet: View {
    public let target: DerivedExportTarget
    public let actions: CaptureRootActions

    @State private var info: DerivedExportInfo?
    @State private var language: SurveyReportLanguage =
        SurveyReportLanguage.preferred
    @State private var selectedFrameIDs: Set<String> = []
    @State private var isExporting = false
    @State private var outcome: DerivedExportOutcome?
    @Environment(\.dismiss) private var dismiss

    public init(
        target: DerivedExportTarget,
        actions: CaptureRootActions
    ) {
        self.target = target
        self.actions = actions
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "A printable HTML report plus an SVG plan, derived from this exact capture revision. It summarizes entities, measurements, mission completeness, and findings — it is not canonical evidence."
                    )
                } header: {
                    Text("What this is")
                }

                Section("Language") {
                    Picker(
                        "Report language",
                        selection: $language
                    ) {
                        Text("English")
                            .tag(SurveyReportLanguage.english)
                        Text("日本語")
                            .tag(SurveyReportLanguage.japanese)
                    }
                    .pickerStyle(.segmented)
                    Text(
                        language == .english
                            ? "The exported survey report is written in English."
                            : "The exported survey report is written in Japanese."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    if let options = info?.evidenceOptions,
                       !options.isEmpty
                    {
                        ForEach(options) { option in
                            evidenceRow(option)
                        }
                        Text(
                            "Only frames you select are embedded as downscaled JPEG previews. The canonical bundle is untouched."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else if info != nil {
                        Text(
                            "No preview-bearing evidence frames are recorded — the report will contain no camera imagery."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Evidence previews (optional)")
                }

                if let failure = info?.failureReason {
                    Section {
                        Text(failure)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        isExporting = true
                        Task {
                            outcome =
                                await actions.exportSurveyReport(
                                    target.revisionID,
                                    SurveyReportSelection(
                                        language: language,
                                        evidenceFrameIDs:
                                            selectedFrameIDs
                                    )
                                )
                            isExporting = false
                        }
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Text("Generate report")
                        }
                    }
                    .disabled(isExporting || info == nil)
                }

                if let outcome {
                    if let error = outcome.error {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    } else if !outcome.files.isEmpty {
                        Section("Exported files") {
                            ForEach(
                                outcome.files,
                                id: \.self
                            ) { file in
                                ShareLink(item: file) {
                                    Label(
                                        file.lastPathComponent,
                                        systemImage:
                                            "square.and.arrow.up"
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Survey report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            info = await actions.derivedExportInfo(
                target.revisionID
            )
        }
    }

    @ViewBuilder
    private func evidenceRow(
        _ option: SurveyReportEvidenceOption
    ) -> some View {
        let selected = selectedFrameIDs.contains(option.id)
        Button {
            if selected {
                selectedFrameIDs.remove(option.id)
            } else {
                selectedFrameIDs.insert(option.id)
            }
        } label: {
            HStack(spacing: 12) {
                #if canImport(UIKit)
                if let image = UIImage(
                    contentsOfFile: option.previewFileURL.path
                ) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "photo")
                        .frame(width: 48, height: 48)
                }
                #else
                Image(systemName: "photo")
                    .frame(width: 48, height: 48)
                #endif
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        String(
                            format: "t=%.1fs",
                            option.sessionTimestampSeconds
                        )
                    )
                    Text(option.frameID.description)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(
                    systemName: selected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(
                    selected ? Color.accentColor : .secondary
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
