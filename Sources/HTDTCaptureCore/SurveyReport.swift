import Foundation

/// Language for the derived field-survey report (issue bolph71656-ai/HTDT-Capture#318).
public enum SurveyReportLanguage:
    String,
    Sendable,
    CaseIterable,
    Identifiable
{
    case english = "en"
    case japanese = "ja"

    public var id: String { rawValue }

    public var localeCode: String { rawValue }

    /// The UI default — follows the app's resolved localization
    /// (legacy bolph71656-ai/HTDT-Capture#399): the same `Localizable.strings` authority that decides
    /// every other string, never raw device preferences.
    public static var preferred: SurveyReportLanguage {
        Bundle.main.preferredLocalizations
            .contains { $0.lowercased().hasPrefix("ja") }
            ? .japanese
            : .english
    }
}

/// One evidence-frame preview explicitly selected for inclusion in a
/// survey report. `jpegData` is produced by the caller (previews are
/// HEIC on disk; the UI converts via ImageIO) — nothing camera-derived
/// is embedded without this explicit selection.
public struct SurveyReportEvidenceImage: Sendable {
    public let frameID: EvidenceFrameID
    public let caption: String?
    public let jpegData: Data

    public init(
        frameID: EvidenceFrameID,
        caption: String? = nil,
        jpegData: Data
    ) {
        self.frameID = frameID
        self.caption = caption
        self.jpegData = jpegData
    }
}

/// A preview-bearing evidence frame the report sheet can offer for
/// selection.
public struct SurveyReportEvidenceOption:
    Sendable,
    Equatable,
    Identifiable
{
    public let frameID: EvidenceFrameID
    public let previewFileURL: URL
    /// `evidence/frames/<id>.preview.heic` — the manifest-declared path.
    public let previewPath: String
    public let sessionTimestampSeconds: Double

    public var id: String { frameID.description }

    public init(
        frameID: EvidenceFrameID,
        previewFileURL: URL,
        previewPath: String,
        sessionTimestampSeconds: Double
    ) {
        self.frameID = frameID
        self.previewFileURL = previewFileURL
        self.previewPath = previewPath
        self.sessionTimestampSeconds = sessionTimestampSeconds
    }
}

/// Enumerates the frames that carry a manifest-declared preview payload
/// — the only frames the report sheet may offer for inclusion.
public enum SurveyReportEvidenceEnumerator {
    public static func options(
        bundleDirectory: URL,
        manifest: BundleManifest
    ) -> [SurveyReportEvidenceOption] {
        let declared = Set(manifest.files.map(\.path))
        var options: [SurveyReportEvidenceOption] = []
        for path in declared.sorted()
        where path.hasPrefix("evidence/frames/")
            && path.hasSuffix(".preview.heic")
        {
            let stem = String(
                path.dropFirst("evidence/frames/".count)
                    .dropLast(".preview.heic".count)
            )
            let fileURL = url(bundleDirectory, path)
            guard FileManager.default.fileExists(
                atPath: fileURL.path
            ),
                  let frameID = EvidenceFrameID(
                      canonicalString: stem
                  )
            else { continue }
            var timestamp = 0.0
            if let data = try? Data(
                contentsOf: url(
                    bundleDirectory,
                    "evidence/frames/" + stem + ".json"
                )
            ),
               let descriptor = try? JSONDecoder().decode(
                   FrameEvidenceDescriptor.self,
                   from: data
               )
            {
                timestamp = descriptor.sessionTimestampSeconds
            }
            options.append(
                SurveyReportEvidenceOption(
                    frameID: frameID,
                    previewFileURL: fileURL,
                    previewPath: path,
                    sessionTimestampSeconds: timestamp
                )
            )
        }
        return options
    }

    private static func url(
        _ directory: URL,
        _ path: String
    ) -> URL {
        path.split(separator: "/").reduce(directory) {
            $0.appendingPathComponent(
                String($1),
                isDirectory: false
            )
        }
    }
}

// MARK: - Plan compositing

/// Builds the plan model the report renders: RoomPlan walls/openings
/// plus annotation markers traced to exact entity records (issue bolph71656-ai/HTDT-Capture#318's
/// "plan symbols traceable to source records" requirement — every
/// annotation marker is labeled with the entity's label/role and its
/// id is recoverable from the entities table).
public enum SurveyPlanCompositor {
    public static func model(
        base: RoomPlanPreviewModel?,
        entities: [CaptureAnnotationEntity],
        openings: OpeningReviewDocument?,
        roomReferenceFrame: RoomReferenceFrameDocument?
    ) -> RoomPlanPreviewModel? {
        var walls = base?.walls ?? []
        var markers = base?.markers ?? []
        var minX = base?.minX ?? .greatestFiniteMagnitude
        var maxX = base?.maxX ?? -.greatestFiniteMagnitude
        var minZ = base?.minZ ?? .greatestFiniteMagnitude
        var maxZ = base?.maxZ ?? -.greatestFiniteMagnitude

        // Operator-declared openings are not in the RoomPlan plan —
        // draw any candidate that carried observed geometry and was not
        // dismissed, labeled with its source lineage token.
        if let openings {
            for candidate in openings.openings {
                guard let center = candidate.centerMeters,
                      candidate.disposition != .intentionallyIgnored
                else { continue }
                // RoomPlan-inferred openings are already drawn on the
                // RoomPlan base plan; skip them there to avoid doubles.
                if base != nil,
                   candidate.source == .roomplanInference
                {
                    continue
                }
                let kind: RoomPlanPreviewModel.PlanMarker.Kind =
                    switch candidate.kind {
                    case .door: .door
                    case .window: .window
                    case .opening, .hvacGrille, .transferGrille,
                         .doorUndercut, .servicePenetration, .other:
                        .opening
                    }
                markers.append(
                    .init(
                        kind: kind,
                        x: center.x,
                        z: center.z,
                        label: candidate.sourceRef
                    )
                )
                minX = min(minX, center.x)
                maxX = max(maxX, center.x)
                minZ = min(minZ, center.z)
                maxZ = max(maxZ, center.z)
            }
        }

        for entity in entities {
            let position = entity.worldFromAnnotation.translationWorld
            let x = Double(position.x)
            let z = Double(position.z)
            var dirX: Double? = nil
            var dirZ: Double? = nil
            if let front = entity.orientation?.frontAxisLocal {
                let world = entity.worldFromAnnotation
                    .applying(toDirection: Float3(
                        front.x, front.y, front.z
                    ))
                let length = (world.x * world.x
                    + world.z * world.z).squareRoot()
                if length > 0.01 {
                    dirX = Double(world.x / length)
                    dirZ = Double(world.z / length)
                }
            }
            let label = entity.channelRole?.rawValue
                ?? entity.listeningRole?.rawValue
                ?? entity.label
            markers.append(
                .init(
                    kind: .annotation,
                    x: x,
                    z: z,
                    dirX: dirX,
                    dirZ: dirZ,
                    label: label
                )
            )
            minX = min(minX, x)
            maxX = max(maxX, x)
            minZ = min(minZ, z)
            maxZ = max(maxZ, z)
        }

        if let frame = roomReferenceFrame {
            let origin = frame.originMeters
            markers.append(
                .init(
                    kind: .roomFrameOrigin,
                    x: origin.x,
                    z: origin.z,
                    label: "room_frame_origin"
                )
            )
            let front = frame.frontDirection
            markers.append(
                .init(
                    kind: .roomFrameFront,
                    x: origin.x + front.x,
                    z: origin.z + front.z,
                    label: "front"
                )
            )
            minX = min(minX, origin.x)
            maxX = max(maxX, origin.x)
            minZ = min(minZ, origin.z)
            maxZ = max(maxZ, origin.z)
        }

        guard !walls.isEmpty || !markers.isEmpty else { return nil }
        return RoomPlanPreviewModel(
            minX: minX,
            maxX: maxX,
            minZ: minZ,
            maxZ: maxZ,
            walls: walls,
            markers: markers
        )
    }
}

// MARK: - SVG plan renderer

/// Renders `RoomPlanPreviewModel` as a standalone SVG document — the
/// same projection the in-app `RoomPlanPreviewCanvas` uses (capture
/// world X→right, Z→down, meters). The output embeds a legend and a
/// scale bar and is valid standalone or inlined into the HTML report.
public enum SurveyPlanRenderer {
    /// Pixels-per-meter scale inside the SVG viewBox.
    private static let pxPerMeter = 64.0
    private static let marginMeters = 0.5

    public static func svg(
        model: RoomPlanPreviewModel,
        language: SurveyReportLanguage
    ) -> String {
        let minX = model.minX - marginMeters
        let minZ = model.minZ - marginMeters
        let spanX = max(model.maxX - model.minX, 0.1)
            + marginMeters * 2
        let spanZ = max(model.maxZ - model.minZ, 0.1)
            + marginMeters * 2
        let widthPx = spanX * pxPerMeter
        let heightPx = spanZ * pxPerMeter

        func sx(_ x: Double) -> String {
            fmt((x - minX) * pxPerMeter)
        }
        func sz(_ z: Double) -> String {
            fmt((z - minZ) * pxPerMeter)
        }

        var s = """
        <svg xmlns="http://www.w3.org/2000/svg" \
        viewBox="0 0 \(fmt(widthPx)) \(fmt(heightPx))" \
        width="\(fmt(widthPx))" height="\(fmt(heightPx))" \
        role="img" aria-label="\(t(.planAriaLabel, language))">
        <desc>\(t(.planAriaLabel, language))</desc>
        <style>
        text { font-family: system-ui, sans-serif; }
        .label { font-size: 9px; fill: #374151; }
        .legend { font-size: 10px; fill: #111827; }
        .note { font-size: 9px; fill: #6b7280; }
        </style>
        <rect x="0" y="0" width="\(fmt(widthPx))" height="\(fmt(heightPx))" fill="#ffffff" stroke="#d1d5db"/>
        """

        for wall in model.walls {
            s += """
            <line x1="\(sx(wall.startX))" y1="\(sz(wall.startZ))" \
            x2="\(sx(wall.endX))" y2="\(sz(wall.endZ))" \
            stroke="#111827" stroke-width="2" stroke-linecap="round"/>
            """
        }

        for marker in model.markers {
            let color = markerColor(marker.kind)
            let cx = (marker.x - minX) * pxPerMeter
            let cy = (marker.z - minZ) * pxPerMeter
            s += """
            <circle cx="\(fmt(cx))" cy="\(fmt(cy))" r="4" fill="\(color)" \
            stroke="#ffffff" stroke-width="1"/>
            """
            if let dirX = marker.dirX, let dirZ = marker.dirZ {
                let len = max(
                    (dirX * dirX + dirZ * dirZ).squareRoot(),
                    0.001
                )
                let ax = fmt(cx + dirX / len * 14)
                let ay = fmt(cy + dirZ / len * 14)
                s += """
                <line x1="\(fmt(cx))" y1="\(fmt(cy))" x2="\(ax)" y2="\(ay)" \
                stroke="\(color)" stroke-width="1.5"/>
                """
            }
            if let label = marker.label, !label.isEmpty {
                s += """
                <text class="label" x="\(fmt(cx + 6))" \
                y="\(fmt(cy - 4))">\(escape(label))</text>
                """
            }
        }

        s += legend(model: model, language: language)
        s += scaleBar(model: model, language: language)
        s += """
        <text class="note" x="6" y="\(fmt(heightPx - 4))">\
        \(t(.planAxisNote, language))</text>
        </svg>
        """
        return s
    }

    private static func markerColor(
        _ kind: RoomPlanPreviewModel.PlanMarker.Kind
    ) -> String {
        switch kind {
        case .door: "#16a34a"
        case .window: "#2563eb"
        case .opening: "#0d9488"
        case .object: "#6b7280"
        case .annotation: "#ea580c"
        case .roomFrameOrigin: "#dc2626"
        case .roomFrameFront: "#9333ea"
        case .revisitFlag: "#f59e0b"
        case .speaker, .display: "#4f46e5"
        case .seat: "#92400e"
        case .screen: "#0891b2"
        case .projector: "#10b981"
        case .measurement, .referencePoint: "#db2777"
        case .genericEntity: "#9ca3af"
        case .plannedTarget: "#6b7280"
        }
    }

    private static func legend(
        model: RoomPlanPreviewModel,
        language: SurveyReportLanguage
    ) -> String {
        let present = Set(model.markers.map(\.kind))
        guard !present.isEmpty else { return "" }
        let entries: [(RoomPlanPreviewModel.PlanMarker.Kind, ReportKey)] = [
            (.door, .legendDoor),
            (.window, .legendWindow),
            (.opening, .legendOpening),
            (.object, .legendObject),
            (.annotation, .legendAnnotation),
            (.roomFrameOrigin, .legendFrameOrigin),
            (.roomFrameFront, .legendFrameFront),
        ]
        var s = "<g>"
        var y = 14.0
        for (kind, key) in entries where present.contains(kind) {
            s += """
            <circle cx="10" cy="\(fmt(y - 3))" r="4" \
            fill="\(markerColor(kind))"/>
            <text class="legend" x="18" y="\(fmt(y))">\
            \(t(key, language))</text>
            """
            y += 14
        }
        return s + "</g>"
    }

    private static func scaleBar(
        model: RoomPlanPreviewModel,
        language: SurveyReportLanguage
    ) -> String {
        // 1 m bar bottom-right when the plan spans at least ~1.5 m.
        let spanX = model.maxX - model.minX
        guard spanX >= 1.5 else { return "" }
        let x1 = (model.maxX + marginMeters / 2 - model.minX + marginMeters)
            * pxPerMeter - pxPerMeter
        let y = (model.maxZ - model.minZ + marginMeters * 2)
            * pxPerMeter - 14
        return """
        <g>
        <line x1="\(fmt(x1))" y1="\(fmt(y))" \
        x2="\(fmt(x1 + pxPerMeter))" y2="\(fmt(y))" \
        stroke="#111827" stroke-width="2"/>
        <text class="legend" x="\(fmt(x1))" y="\(fmt(y - 4))">1 m</text>
        </g>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

// MARK: - Report document

/// Everything the report builder reads — already decoded, so the
/// builder is pure string composition testable on macOS.
public struct SurveyReportInput: Sendable {
    public let contents: PersistedCaptureContents
    public let advisoryReport: CaptureAdvisoryReport?
    /// Plan model already composited with annotation/opening markers.
    public let planPreview: RoomPlanPreviewModel?
    public let displayName: String?
    public let bundleDigest: EvidenceSHA256
    /// Previews explicitly selected by the operator — never populated
    /// by default.
    public let evidenceImages: [SurveyReportEvidenceImage]
    public let language: SurveyReportLanguage
    public let generatedAtUTC: String

    public init(
        contents: PersistedCaptureContents,
        advisoryReport: CaptureAdvisoryReport?,
        planPreview: RoomPlanPreviewModel?,
        displayName: String?,
        bundleDigest: EvidenceSHA256,
        evidenceImages: [SurveyReportEvidenceImage],
        language: SurveyReportLanguage,
        generatedAtUTC: String
    ) {
        self.contents = contents
        self.advisoryReport = advisoryReport
        self.planPreview = planPreview
        self.displayName = displayName
        self.bundleDigest = bundleDigest
        self.evidenceImages = evidenceImages
        self.language = language
        self.generatedAtUTC = generatedAtUTC
    }
}

/// Provenance record written as `<name>.provenance.json` beside the
/// report so the document is reproducibly linked to the exact capture
/// revision + bundle digest it was derived from.
public struct DerivedDocumentProvenance:
    Codable,
    Sendable,
    Equatable
{
    public static let expectedSchema = "htdt.derived-document"
    public static let expectedSchemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let derivedArtifact: Bool
    public let documentKind: String
    public let captureSeriesID: CaptureSeriesID
    public let captureRevisionID: CaptureRevisionID
    public let bundleDigest: EvidenceSHA256
    public let sourceCoordinateSpaceIDs: [CoordinateSpaceID]
    public let sourcePayloads: [DerivedExportSourcePayload]
    public let language: String
    public let exporterName: String
    public let exporterVersion: String
    public let producerApp: BundleAppIdentity?
    public let generatedAtUTC: String

    public init(
        documentKind: String,
        captureSeriesID: CaptureSeriesID,
        captureRevisionID: CaptureRevisionID,
        bundleDigest: EvidenceSHA256,
        sourceCoordinateSpaceIDs: [CoordinateSpaceID],
        sourcePayloads: [DerivedExportSourcePayload],
        language: String,
        producerApp: BundleAppIdentity?,
        generatedAtUTC: String
    ) {
        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.derivedArtifact = true
        self.documentKind = documentKind
        self.captureSeriesID = captureSeriesID
        self.captureRevisionID = captureRevisionID
        self.bundleDigest = bundleDigest
        self.sourceCoordinateSpaceIDs = sourceCoordinateSpaceIDs
        self.sourcePayloads = sourcePayloads
        self.language = language
        self.exporterName = "HTDTCapture survey-report"
        self.exporterVersion = "1.0.0"
        self.producerApp = producerApp
        self.generatedAtUTC = generatedAtUTC
    }
}

/// Builds the standalone bilingual field-survey report as a single
/// self-contained HTML document (printable, shareable, no external
/// resources). Never emits camera imagery unless a preview was
/// explicitly supplied in the input.
public enum SurveyReportBuilder {
    public static func html(
        input: SurveyReportInput
    ) -> String {
        let language = input.language
        let manifest = input.contents.manifest
        var body = """
        <!DOCTYPE html>
        <html lang="\(language.localeCode)">
        <head>
        <meta charset="utf-8"/>
        <title>\(esc(t(.title, language)))</title>
        <style>
        body { font-family: system-ui, sans-serif; color: #111827;
               margin: 2em; max-width: 900px; }
        h1 { font-size: 1.4em; } h2 { font-size: 1.05em;
             border-bottom: 1px solid #d1d5db; padding-bottom: 2px;
             margin-top: 1.6em; }
        table { border-collapse: collapse; width: 100%;
                font-size: 0.85em; }
        th, td { border: 1px solid #d1d5db; padding: 3px 7px;
                 text-align: left; vertical-align: top; }
        th { background: #f3f4f6; }
        .banner { background: #fef3c7; border: 1px solid #f59e0b;
                  padding: 8px 12px; border-radius: 6px;
                  font-size: 0.9em; }
        .mono { font-family: ui-monospace, monospace;
                font-size: 0.85em; word-break: break-all; }
        .missing { color: #b91c1c; }
        .note { color: #4b5563; font-size: 0.85em; }
        .evidence img { max-width: 320px; border: 1px solid #d1d5db;
                        margin: 4px 8px 4px 0; }
        @media print { body { margin: 0.5cm; } }
        </style>
        </head>
        <body>
        <h1>\(esc(t(.title, language)))</h1>
        <p class="banner">\(esc(t(.derivedBanner, language)))</p>
        """

        body += headerSection(input: input, manifest: manifest)
        body += planSection(input: input)
        body += entitiesSection(input: input)
        body += measurementsSection(input: input)
        body += missionSection(input: input)
        body += findingsSection(input: input)
        body += fieldNotesSection(input: input)
        body += evidenceSection(input: input)
        body += provenanceSection(input: input, manifest: manifest)
        body += "</body>\n</html>\n"
        return body
    }

    // MARK: sections

    private static func headerSection(
        input: SurveyReportInput,
        manifest: BundleManifest
    ) -> String {
        let language = input.language
        var rows: [(String, String)] = [
            (t(.captureRevision, language),
             manifest.captureRevisionID.description),
            (t(.captureSeries, language),
             manifest.captureSeriesID.description),
            (t(.bundleDigest, language),
             input.bundleDigest.description),
            (t(.finalizedAt, language), manifest.finalizedAtUTC),
            (t(.captureSessions, language),
             manifest.captureSessionIDs
                 .map(\.description).joined(separator: ", ")),
            (t(.coordinateSpaces, language),
             manifest.coordinateSpaceIDs
                 .map(\.description).joined(separator: ", ")),
            (t(.producedBy, language),
             "\(manifest.app.name) \(manifest.app.version) (\(manifest.app.build))"),
            (t(.reportGeneratedAt, language), input.generatedAtUTC),
            (t(.declaredOperator, language),
             t(.notRecorded, language)),
        ]
        if let name = input.displayName, !name.isEmpty {
            rows.insert(
                (t(.captureName, language), esc(name)),
                at: 0
            )
        }
        if let parent = manifest.parentRevisionID {
            rows.append(
                (t(.revisesRevision, language), parent.description)
            )
        }
        var html = "<h2>\(esc(t(.sectionIdentity, language)))</h2><table>"
        for (label, value) in rows {
            html += "<tr><th>\(esc(label))</th><td class=\"mono\">\(value)</td></tr>"
        }
        return html + "</table>"
    }

    private static func planSection(
        input: SurveyReportInput
    ) -> String {
        let language = input.language
        var html = "<h2>\(esc(t(.sectionPlan, language)))</h2>"
        if let plan = input.planPreview {
            html += SurveyPlanRenderer.svg(
                model: plan,
                language: language
            )
            html += "<p class=\"note\">"
                + esc(t(.planNote, language)) + "</p>"
        } else {
            html += "<p class=\"note\">"
                + esc(t(.planUnavailable, language)) + "</p>"
        }
        return html
    }

    private static func entitiesSection(
        input: SurveyReportInput
    ) -> String {
        let language = input.language
        let entities = input.contents.entities
        var html = "<h2>\(esc(t(.sectionEntities, language)))</h2>"
        guard !entities.isEmpty else {
            return html + "<p class=\"note\">"
                + esc(t(.noEntities, language)) + "</p>"
        }
        html += "<table><tr>"
        for header in [
            t(.entityLabel, language),
            t(.entityType, language),
            t(.entityRole, language),
            t(.entityVerification, language),
            t(.entityPlacement, language),
            t(.entityUncertainty, language),
            t(.entityID, language),
        ] {
            html += "<th>\(esc(header))</th>"
        }
        html += "</tr>"
        for entity in entities {
            let role = entity.channelRole?.rawValue
                ?? entity.listeningRole?.rawValue
                ?? "—"
            let uncertainty =
                uncertaintyText(entity.uncertainty)
            html += "<tr><td>\(esc(entity.label))</td>"
            html += "<td>\(entity.type.rawValue)</td>"
            html += "<td>\(esc(role))</td>"
            html += "<td>\(entity.verificationState.rawValue)</td>"
            html += "<td>\(entity.placement.method.rawValue)</td>"
            html += "<td>\(esc(uncertainty))</td>"
            html += "<td class=\"mono\">\(entity.entityID.description)</td></tr>"
        }
        return html + "</table>"
    }

    private static func measurementsSection(
        input: SurveyReportInput
    ) -> String {
        let language = input.language
        let measurements = input.contents.measurements
        var html = "<h2>\(esc(t(.sectionMeasurements, language)))</h2>"
        guard !measurements.isEmpty else {
            return html + "<p class=\"note\">"
                + esc(t(.noMeasurements, language)) + "</p>"
        }
        html += "<table><tr>"
        for header in [
            t(.measurementQuantity, language),
            t(.measurementValue, language),
            t(.measurementMethod, language),
            t(.measurementUncertainty, language),
            t(.measurementObserved, language),
            t(.measurementEndpoints, language),
            t(.measurementID, language),
        ] {
            html += "<th>\(esc(header))</th>"
        }
        html += "</tr>"
        for measurement in measurements {
            html += "<tr><td>\(esc(measurement.quantityType))</td>"
            html += "<td>\(esc(valueText(measurement.value))) \(measurement.unit.rawValue)</td>"
            html += "<td>\(measurement.acquisitionMethod.rawValue)</td>"
            html += "<td>\(measurement.statedUncertainty.map { "±" + fmt($0) } ?? t(.unknown, language))</td>"
            html += "<td>\(measurement.observedAtUTC ?? t(.unknown, language))</td>"
            html += "<td class=\"mono\">\(esc(measurement.endpointRefs.joined(separator: ", ")))</td>"
            html += "<td class=\"mono\">\(measurement.measurementID.description)</td></tr>"
        }
        return html + "</table>"
    }

    private static func missionSection(
        input: SurveyReportInput
    ) -> String {
        let language = input.language
        var html = "<h2>\(esc(t(.sectionMission, language)))</h2>"
        guard let report =
            input.advisoryReport?.taskCompleteness
        else {
            return html + "<p class=\"note\">"
                + esc(t(.missionUnavailable, language)) + "</p>"
        }
        html += "<table>"
        html += "<tr><th>\(esc(t(.missionProfile, language)))</th><td>\(esc(report.profileTitle ?? report.profileIdentifier ?? "—"))</td></tr>"
        html += "<tr><th>\(esc(t(.missionState, language)))</th><td>\(report.evaluationState.rawValue)</td></tr>"
        html += "<tr><th>\(esc(t(.missionOverall, language)))</th><td>\(report.overallSatisfied ? t(.yes, language) : t(.no, language))</td></tr>"
        html += "<tr><th>\(esc(t(.missionUnsatisfied, language)))</th><td>\(report.requiredUnsatisfiedCount)</td></tr>"
        html += "</table>"
        let unsatisfied = report.outcomes.filter {
            $0.status == .missing
                || $0.status == .partial
                || $0.status == .overMaximum
        }
        if !unsatisfied.isEmpty {
            html += "<table><tr><th>\(esc(t(.missionRequirement, language)))</th><th>\(esc(t(.missionStatus, language)))</th><th>\(esc(t(.missionObserved, language)))</th></tr>"
            for outcome in unsatisfied {
                html += "<tr><td>\(esc(outcome.requirement.identifier))</td><td>\(outcome.status.rawValue)</td><td>\(outcome.observedCount)</td></tr>"
            }
            html += "</table>"
        }
        return html
    }

    private static func findingsSection(
        input: SurveyReportInput
    ) -> String {
        let language = input.language
        var html = "<h2>\(esc(t(.sectionFindings, language)))</h2>"
        var items: [String] = []

        if let quality = input.contents.qualityReport {
            items.append(
                "\(t(.qualityIntegrity, language)): \(quality.integrityStatus.rawValue); \(t(.qualityRoomPlan, language)): \(quality.roomPlanStatus.rawValue)"
            )
            let missingAnnotations =
                quality.annotationCompleteness.missing
            let missingMeasurements =
                quality.measurementCompleteness.missing
            if !missingAnnotations.isEmpty {
                items.append(
                    "<span class=\"missing\">"
                        + esc(t(.missingAnnotations, language))
                        + ": "
                        + esc(missingAnnotations.joined(separator: ", "))
                        + "</span>"
                )
            }
            if !missingMeasurements.isEmpty {
                items.append(
                    "<span class=\"missing\">"
                        + esc(t(.missingMeasurements, language))
                        + ": "
                        + esc(missingMeasurements.joined(separator: ", "))
                        + "</span>"
                )
            }
            for diagnostic in quality.diagnostics {
                items.append(
                    "[\(diagnostic.severity.rawValue)] \(esc(diagnostic.code)) — \(esc(diagnostic.message))"
                )
            }
        }

        if let consistency =
            input.advisoryReport?.geometryConsistency
        {
            if !consistency.discrepantAxes.isEmpty {
                items.append(
                    "<span class=\"missing\">"
                        + esc(t(.geometryDiscrepancy, language))
                        + ": "
                        + esc(consistency.discrepantAxes.joined(separator: ", "))
                        + "</span>"
                )
            }
        }
        if let conflicts = input.advisoryReport?.conflicts {
            switch conflicts.status {
            case .unavailable:
                items.append(
                    esc(t(.conflictsUnavailable, language))
                )
            case .analyzed:
                for conflict in conflicts.conflicts {
                    items.append(
                        "\(conflict.kind.rawValue) — \(esc(conflict.subject)): \(esc(conflict.detail))"
                    )
                }
            }
        }
        if let openings = input.contents.openingReview {
            let unreviewed = openings.openings.filter {
                $0.disposition == .unreviewed
            }
            if !unreviewed.isEmpty {
                items.append(
                    "<span class=\"missing\">"
                        + "\(unreviewed.count) "
                        + esc(t(.unreviewedOpenings, language))
                        + "</span>"
                )
            }
        }
        for issue in input.contents.issues {
            items.append(esc(issue))
        }

        if items.isEmpty {
            return html + "<p class=\"note\">"
                + esc(t(.noFindings, language)) + "</p>"
        }
        html += "<ul>"
        for item in items {
            html += "<li>\(item)</li>"
        }
        return html + "</ul>"
    }

    /// Operator field notes (legacy bolph71656-ai/HTDT-Capture#459): the notes recorded during the
    /// scan reach the report — they were previously persisted in the
    /// bundle but never rendered into the export the receiving side
    /// reads.
    private static func fieldNotesSection(
        input: SurveyReportInput
    ) -> String {
        let language = input.language
        var html = "<h2>\(esc(t(.sectionFieldNotes, language)))</h2>"
        let notes = input.contents.fieldNotes
        guard !notes.isEmpty else {
            return html + "<p class=\"note\">"
                + esc(t(.noFieldNotes, language)) + "</p>"
        }
        html += "<ul>"
        for note in notes {
            var tags = [
                esc(fieldNoteCategoryName(note.category, language)),
                esc(fieldNoteStatusName(note.status, language)),
            ]
            if let severity = note.severity {
                tags.append(
                    esc(t(.fieldNoteSeverity, language)) + ": "
                        + esc(
                            fieldNoteSeverityName(
                                severity,
                                language
                            )
                        )
                )
            }
            if note.needsAttention {
                tags.append(esc(t(.fieldNoteNeedsAttention, language)))
            }
            html += "<li><strong>\(esc(note.text))</strong><br>"
                + "<span class=\"note\">"
                + tags.joined(separator: " · ")
                + " — \(esc(t(.fieldNoteRecorded, language))): "
                + "\(esc(note.createdAtUTC))"
                + "</span></li>"
        }
        return html + "</ul>"
    }

    private static func fieldNoteCategoryName(
        _ category: CaptureFieldNoteCategory,
        _ language: SurveyReportLanguage
    ) -> String {
        switch category.rawValue {
        case "room_condition":
            return t(.fieldNoteCategoryRoomCondition, language)
        case "obstruction":
            return t(.fieldNoteCategoryObstruction, language)
        case "equipment_state":
            return t(.fieldNoteCategoryEquipmentState, language)
        case "geometry_caveat":
            return t(.fieldNoteCategoryGeometryCaveat, language)
        case "measurement_caveat":
            return t(.fieldNoteCategoryMeasurementCaveat, language)
        case "follow_up":
            return t(.fieldNoteCategoryFollowUp, language)
        case "installation_observation":
            return t(.fieldNoteCategoryInstallationObservation, language)
        case "general":
            return t(.fieldNoteCategoryGeneral, language)
        default:
            // `x_` extension categories carry no shared vocabulary —
            // render the deployment's token verbatim.
            return category.rawValue
        }
    }

    private static func fieldNoteStatusName(
        _ status: CaptureFieldNoteStatus,
        _ language: SurveyReportLanguage
    ) -> String {
        switch status {
        case .active:
            return t(.fieldNoteStatusActive, language)
        case .resolved:
            return t(.fieldNoteStatusResolved, language)
        case .superseded:
            return t(.fieldNoteStatusSuperseded, language)
        }
    }

    private static func fieldNoteSeverityName(
        _ severity: CaptureFieldNoteSeverity,
        _ language: SurveyReportLanguage
    ) -> String {
        switch severity {
        case .observation:
            return t(.fieldNoteSeverityObservation, language)
        case .concern:
            return t(.fieldNoteSeverityConcern, language)
        case .hazard:
            return t(.fieldNoteSeverityHazard, language)
        }
    }

    private static func evidenceSection(
        input: SurveyReportInput
    ) -> String {
        let language = input.language
        var html = "<h2>\(esc(t(.sectionEvidence, language)))</h2>"
        let descriptorCount = input.contents.frameDescriptors.count
        html += "<table>"
        html += "<tr><th>\(esc(t(.evidenceFrames, language)))</th><td>\(descriptorCount)</td></tr>"
        if let quality = input.contents.qualityReport {
            html += "<tr><th>\(esc(t(.depthFrames, language)))</th><td>\(quality.depthEvidenceCount)</td></tr>"
        }
        html += "</table>"
        if input.evidenceImages.isEmpty {
            html += "<p class=\"note\">"
                + esc(t(.noEvidenceSelected, language)) + "</p>"
        } else {
            html += "<p class=\"note\">"
                + esc(t(.evidenceSelectedNote, language)) + "</p>"
            html += "<div class=\"evidence\">"
            for image in input.evidenceImages {
                let base64 = image.jpegData.base64EncodedString()
                let caption = image.caption
                    ?? image.frameID.description
                html += """
                <figure style="display:inline-block;margin:0 8px 8px 0">
                <img src="data:image/jpeg;base64,\(base64)" alt="\(esc(caption))"/>
                <figcaption class="note">\(esc(caption))</figcaption>
                </figure>
                """
            }
            html += "</div>"
        }
        return html
    }

    private static func provenanceSection(
        input: SurveyReportInput,
        manifest: BundleManifest
    ) -> String {
        let language = input.language
        var html = "<h2>\(esc(t(.sectionProvenance, language)))</h2>"
        html += "<p class=\"note\">"
            + esc(t(.provenanceNote, language)) + "</p>"
        html += "<table>"
        html += "<tr><th>\(esc(t(.sourcePayloads, language)))</th><td class=\"mono\">\(esc(manifest.files.map(\.path).sorted().joined(separator: ", ")))</td></tr>"
        html += "<tr><th>\(esc(t(.reportExporter, language)))</th><td>HTDTCapture survey-report 1.0.0</td></tr>"
        html += "</table>"
        return html
    }

    // MARK: helpers

    private static func valueText(
        _ value: MeasurementValue
    ) -> String {
        switch value {
        case .scalar(let scalar):
            fmt(scalar)
        case .vector3(let x, let y, let z):
            "(\(fmt(x)), \(fmt(y)), \(fmt(z)))"
        }
    }

    private static func uncertaintyText(
        _ uncertainty: SpatialUncertaintyAuthority?
    ) -> String {
        guard let uncertainty else { return "—" }
        var parts: [String] = []
        if let iso = uncertainty.isotropicMeters {
            parts.append("±\(fmt(iso)) m")
        }
        if let perAxis = uncertainty.perAxisMeters {
            parts.append(
                "±(\(fmt(perAxis.x)), \(fmt(perAxis.y)), \(fmt(perAxis.z))) m"
            )
        }
        if let angular = uncertainty.angularRadians {
            parts.append("±\(fmt(angular)) rad")
        }
        let basis = uncertainty.basis.rawValue
        return (parts.isEmpty ? "—" : parts.joined(separator: " "))
            + " [\(basis)]"
    }

    static func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    static func fmt(_ value: Float) -> String {
        fmt(Double(value))
    }

    static func esc(_ text: String) -> String {
        SurveyPlanRenderer.escape(text)
    }
}

// MARK: - Report writer

/// Writes the survey report artifacts under
/// `<captureRoot>/derived-exports/<revision>/` alongside derived 3D
/// exports: `<stem>.html`, `<stem>-plan.svg` (when a plan exists), and
/// `<stem>.provenance.json` binding the document to the exact capture
/// revision and bundle digest (issue bolph71656-ai/HTDT-Capture#318).
public enum SurveyReportRunner {
    public struct Result: Sendable, Equatable {
        public let reportFileURL: URL
        public let planFileURL: URL?
        public let provenanceFileURL: URL

        /// Every produced file, share-sheet order.
        public var files: [URL] {
            var files = [reportFileURL]
            if let planFileURL { files.append(planFileURL) }
            files.append(provenanceFileURL)
            return files
        }
    }

    /// `evidenceImages` must be empty unless the operator explicitly
    /// selected previews — the caller (UI) enforces this.
    public static func export(
        bundleDirectory: URL,
        bundleDigest: EvidenceSHA256,
        captureRoot: URL,
        displayName: String?,
        planPreview: RoomPlanPreviewModel?,
        evidenceImages: [SurveyReportEvidenceImage],
        language: SurveyReportLanguage,
        generatedAtUTC: String? = nil
    ) throws -> Result {
        let manifest = try DerivedExportRunner.loadManifest(
            bundleDirectory: bundleDirectory
        )
        let contents: PersistedCaptureContents
        do {
            contents = try PersistedCaptureContentsLoader.load(
                directory: bundleDirectory
            )
        } catch {
            throw DerivedExportError.malformedSource(
                reason:
                    "the finalized bundle's payloads could not be decoded: \(error.localizedDescription)"
            )
        }
        let advisory = loadAdvisory(
            bundleDirectory: bundleDirectory,
            manifest: manifest
        )
        let timestamp =
            generatedAtUTC ?? BundleTimestamp.utcString(from: Date())

        let plan = SurveyPlanCompositor.model(
            base: planPreview,
            entities: contents.entities,
            openings: contents.openingReview,
            roomReferenceFrame: contents.roomReferenceFrame
        )

        let input = SurveyReportInput(
            contents: contents,
            advisoryReport: advisory,
            planPreview: plan,
            displayName: displayName,
            bundleDigest: bundleDigest,
            evidenceImages: evidenceImages,
            language: language,
            generatedAtUTC: timestamp
        )
        let html = SurveyReportBuilder.html(input: input)

        let stem = "capture-\(manifest.captureRevisionID)-survey-\(language.rawValue)"
        let directory = DerivedExportRunner.exportsDirectory(
            captureRoot: captureRoot,
            revisionID: manifest.captureRevisionID
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw DerivedExportError.writeFailed(
                reason:
                    "derived-exports directory could not be created: \(error.localizedDescription)"
            )
        }
        let reportURL = directory.appendingPathComponent(
            stem + ".html",
            isDirectory: false
        )
        do {
            try Data(html.utf8).write(to: reportURL)
        } catch {
            throw DerivedExportError.writeFailed(
                reason:
                    "the report file could not be written: \(error.localizedDescription)"
            )
        }

        var planURL: URL? = nil
        if let plan {
            let svgURL = directory.appendingPathComponent(
                "capture-\(manifest.captureRevisionID)-plan.svg",
                isDirectory: false
            )
            do {
                try Data(
                    SurveyPlanRenderer.svg(
                        model: plan,
                        language: language
                    ).utf8
                ).write(to: svgURL)
                planURL = svgURL
            } catch {
                throw DerivedExportError.writeFailed(
                    reason:
                        "the plan SVG could not be written: \(error.localizedDescription)"
                )
            }
        }

        let provenance = DerivedDocumentProvenance(
            documentKind: "field_survey_report",
            captureSeriesID: manifest.captureSeriesID,
            captureRevisionID: manifest.captureRevisionID,
            bundleDigest: bundleDigest,
            sourceCoordinateSpaceIDs: manifest.coordinateSpaceIDs,
            sourcePayloads: manifest.files
                .map(\.path)
                .sorted()
                .compactMap { path -> DerivedExportSourcePayload? in
                    let fileURL = path.split(separator: "/")
                        .reduce(bundleDirectory) {
                            $0.appendingPathComponent(
                                String($1),
                                isDirectory: false
                            )
                        }
                    guard let data = try? Data(
                        contentsOf: fileURL
                    )
                    else { return nil }
                    return DerivedExportSourcePayload(
                        path: path,
                        sha256: EvidenceIntegrity.sha256(of: data),
                        byteCount: data.count
                    )
                },
            language: language.rawValue,
            producerApp: manifest.app,
            generatedAtUTC: timestamp
        )
        let provenanceURL = directory.appendingPathComponent(
            stem + ".provenance.json",
            isDirectory: false
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .sortedKeys, .prettyPrinted,
                .withoutEscapingSlashes,
            ]
            try encoder.encode(provenance).write(to: provenanceURL)
        } catch {
            throw DerivedExportError.writeFailed(
                reason:
                    "the provenance record could not be written: \(error.localizedDescription)"
            )
        }

        return Result(
            reportFileURL: reportURL,
            planFileURL: planURL,
            provenanceFileURL: provenanceURL
        )
    }

    /// Same manifest-authenticated decode pattern the host uses for
    /// the advisory payload (`quality/capture-advisory.json`).
    private static func loadAdvisory(
        bundleDirectory: URL,
        manifest: BundleManifest
    ) -> CaptureAdvisoryReport? {
        let path = CaptureAdvisoryReport.payloadPath
        guard manifest.files.contains(where: { $0.path == path })
        else { return nil }
        let url = path.split(separator: "/").reduce(bundleDirectory) {
            $0.appendingPathComponent(
                String($1),
                isDirectory: false
            )
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(
            CaptureAdvisoryReport.self,
            from: data
        )
    }
}

// MARK: - Strings

/// Report string keys — each has an English and Japanese text.
enum ReportKey: String {
    case title
    case derivedBanner
    case sectionIdentity
    case captureName
    case captureRevision
    case captureSeries
    case bundleDigest
    case finalizedAt
    case captureSessions
    case coordinateSpaces
    case producedBy
    case reportGeneratedAt
    case declaredOperator
    case notRecorded
    case revisesRevision
    case sectionPlan
    case planNote
    case planUnavailable
    case planAriaLabel
    case planAxisNote
    case legendDoor
    case legendWindow
    case legendOpening
    case legendObject
    case legendAnnotation
    case legendFrameOrigin
    case legendFrameFront
    case sectionEntities
    case noEntities
    case entityLabel
    case entityType
    case entityRole
    case entityVerification
    case entityPlacement
    case entityUncertainty
    case entityID
    case sectionMeasurements
    case noMeasurements
    case measurementQuantity
    case measurementValue
    case measurementMethod
    case measurementUncertainty
    case measurementObserved
    case measurementEndpoints
    case measurementID
    case sectionMission
    case missionUnavailable
    case missionProfile
    case missionState
    case missionOverall
    case missionUnsatisfied
    case missionRequirement
    case missionStatus
    case missionObserved
    case sectionFindings
    case qualityIntegrity
    case qualityRoomPlan
    case missingAnnotations
    case missingMeasurements
    case geometryDiscrepancy
    case conflictsUnavailable
    case unreviewedOpenings
    case noFindings
    case sectionEvidence
    case evidenceFrames
    case depthFrames
    case noEvidenceSelected
    case evidenceSelectedNote
    case sectionProvenance
    case provenanceNote
    case sourcePayloads
    case reportExporter
    case sectionFieldNotes
    case noFieldNotes
    case fieldNoteRecorded
    case fieldNoteNeedsAttention
    case fieldNoteSeverity
    case fieldNoteCategoryRoomCondition
    case fieldNoteCategoryObstruction
    case fieldNoteCategoryEquipmentState
    case fieldNoteCategoryGeometryCaveat
    case fieldNoteCategoryMeasurementCaveat
    case fieldNoteCategoryFollowUp
    case fieldNoteCategoryInstallationObservation
    case fieldNoteCategoryGeneral
    case fieldNoteStatusActive
    case fieldNoteStatusResolved
    case fieldNoteStatusSuperseded
    case fieldNoteSeverityObservation
    case fieldNoteSeverityConcern
    case fieldNoteSeverityHazard
    case unknown
    case yes
    case no
}

func t(_ key: ReportKey, _ language: SurveyReportLanguage) -> String {
    switch language {
    case .english:
        switch key {
        case .title: "Field Survey Report"
        case .derivedBanner:
            "Derived document — not canonical capture evidence. The .htdtcapture bundle remains the authoritative record; this report is a reading convenience only."
        case .sectionIdentity: "Capture identity"
        case .captureName: "Capture name"
        case .captureRevision: "Capture revision"
        case .captureSeries: "Capture series"
        case .bundleDigest: "Bundle digest (SHA-256)"
        case .finalizedAt: "Finalized at (UTC)"
        case .captureSessions: "Capture sessions"
        case .coordinateSpaces: "Coordinate spaces"
        case .producedBy: "Produced by"
        case .reportGeneratedAt: "Report generated at (UTC)"
        case .declaredOperator: "Declared operator"
        case .notRecorded: "not recorded"
        case .revisesRevision: "Revises"
        case .sectionPlan: "Top-down plan"
        case .planNote:
            "Plan is drawn in capture world space (X→right, Z→down), meters. Annotation markers are labeled with the entity's role or label."
        case .planUnavailable:
            "No plan geometry is recorded in this capture — no RoomPlan plan, no annotation positions, and no room frame were available."
        case .planAriaLabel: "Top-down floor plan in meters"
        case .planAxisNote:
            "Capture world X→right, Z→down; meters."
        case .legendDoor: "Door"
        case .legendWindow: "Window"
        case .legendOpening: "Opening"
        case .legendObject: "Object"
        case .legendAnnotation: "Annotation"
        case .legendFrameOrigin: "Room frame origin"
        case .legendFrameFront: "Room frame front"
        case .sectionEntities: "Entities"
        case .noEntities: "No committed entities in this capture."
        case .entityLabel: "Label"
        case .entityType: "Type"
        case .entityRole: "Role"
        case .entityVerification: "Verification"
        case .entityPlacement: "Placement"
        case .entityUncertainty: "Uncertainty"
        case .entityID: "Entity ID"
        case .sectionMeasurements: "Measurements"
        case .noMeasurements:
            "No committed measurements in this capture."
        case .measurementQuantity: "Quantity"
        case .measurementValue: "Value"
        case .measurementMethod: "Method"
        case .measurementUncertainty: "Uncertainty"
        case .measurementObserved: "Observed at (UTC)"
        case .measurementEndpoints: "Endpoints"
        case .measurementID: "Measurement ID"
        case .sectionMission: "Mission completeness"
        case .missionUnavailable:
            "No mission-profile evaluation was recorded for this capture."
        case .missionProfile: "Task profile"
        case .missionState: "Evaluation state"
        case .missionOverall: "All required items satisfied"
        case .missionUnsatisfied: "Required items unsatisfied"
        case .missionRequirement: "Requirement"
        case .missionStatus: "Status"
        case .missionObserved: "Observed"
        case .sectionFindings: "Findings and quality"
        case .qualityIntegrity: "Integrity preflight"
        case .qualityRoomPlan: "RoomPlan status"
        case .missingAnnotations: "Missing required annotations"
        case .missingMeasurements: "Missing required measurements"
        case .geometryDiscrepancy:
            "RoomPlan-vs-mesh extent discrepancy on axes"
        case .conflictsUnavailable:
            "Conflict analysis was unavailable for this capture."
        case .unreviewedOpenings: "opening candidate(s) still unreviewed"
        case .noFindings:
            "No findings — the capture passed every recorded check."
        case .sectionEvidence: "Evidence"
        case .evidenceFrames: "Evidence frames retained"
        case .depthFrames: "Depth payloads retained"
        case .noEvidenceSelected:
            "No camera imagery included — previews are embedded only when explicitly selected before export."
        case .evidenceSelectedNote:
            "The previews below were explicitly selected for inclusion. Full-resolution frames remain only in the .htdtcapture bundle."
        case .sectionProvenance: "Provenance"
        case .provenanceNote:
            "This document is derived from the exact capture revision and bundle digest above; every source payload was read from the finalized bundle."
        case .sourcePayloads: "Source payloads"
        case .reportExporter: "Exporter"
        case .sectionFieldNotes: "Field notes"
        case .noFieldNotes:
            "No field notes were recorded during this capture."
        case .fieldNoteRecorded: "Recorded at (UTC)"
        case .fieldNoteNeedsAttention: "needs attention"
        case .fieldNoteSeverity: "severity"
        case .fieldNoteCategoryRoomCondition: "room condition"
        case .fieldNoteCategoryObstruction: "obstruction"
        case .fieldNoteCategoryEquipmentState: "equipment state"
        case .fieldNoteCategoryGeometryCaveat: "geometry caveat"
        case .fieldNoteCategoryMeasurementCaveat: "measurement caveat"
        case .fieldNoteCategoryFollowUp: "follow-up"
        case .fieldNoteCategoryInstallationObservation:
            "installation observation"
        case .fieldNoteCategoryGeneral: "general"
        case .fieldNoteStatusActive: "active"
        case .fieldNoteStatusResolved: "resolved"
        case .fieldNoteStatusSuperseded: "superseded"
        case .fieldNoteSeverityObservation: "observation"
        case .fieldNoteSeverityConcern: "concern"
        case .fieldNoteSeverityHazard: "hazard"
        case .unknown: "unknown"
        case .yes: "yes"
        case .no: "no"
        }
    case .japanese:
        switch key {
        case .title: "フィールド調査レポート"
        case .derivedBanner:
            "派生ドキュメント — 正規のキャプチャ証拠ではありません。.htdtcapture バンドルが権威ある記録であり、このレポートは参照用の便宜出力です。"
        case .sectionIdentity: "キャプチャ識別情報"
        case .captureName: "キャプチャ名"
        case .captureRevision: "キャプチャリビジョン"
        case .captureSeries: "キャプチャシリーズ"
        case .bundleDigest: "バンドルダイジェスト (SHA-256)"
        case .finalizedAt: "ファイナライズ日時 (UTC)"
        case .captureSessions: "キャプチャセッション"
        case .coordinateSpaces: "座標空間"
        case .producedBy: "生成元"
        case .reportGeneratedAt: "レポート生成日時 (UTC)"
        case .declaredOperator: "宣言オペレーター"
        case .notRecorded: "記録なし"
        case .revisesRevision: "改訂元"
        case .sectionPlan: "上面プラン"
        case .planNote:
            "プランはキャプチャワールド空間で描画（X→右、Z→下）、単位メートル。注釈マーカーはエンティティのロールまたはラベルで表示。"
        case .planUnavailable:
            "このキャプチャにはプラン描画に使えるジオメトリが記録されていません（RoomPlan プラン・注釈位置・ルームフレームいずれもなし）。"
        case .planAriaLabel: "上面図（メートル）"
        case .planAxisNote:
            "キャプチャワールド X→右、Z→下、単位メートル。"
        case .legendDoor: "ドア"
        case .legendWindow: "窓"
        case .legendOpening: "開口部"
        case .legendObject: "オブジェクト"
        case .legendAnnotation: "注釈"
        case .legendFrameOrigin: "ルームフレーム原点"
        case .legendFrameFront: "ルームフレーム正面"
        case .sectionEntities: "エンティティ"
        case .noEntities: "コミット済みエンティティはありません。"
        case .entityLabel: "ラベル"
        case .entityType: "種別"
        case .entityRole: "ロール"
        case .entityVerification: "検証状態"
        case .entityPlacement: "配置方法"
        case .entityUncertainty: "不確かさ"
        case .entityID: "エンティティ ID"
        case .sectionMeasurements: "計測"
        case .noMeasurements:
            "コミット済み計測はありません。"
        case .measurementQuantity: "量"
        case .measurementValue: "値"
        case .measurementMethod: "方法"
        case .measurementUncertainty: "不確かさ"
        case .measurementObserved: "観測日時 (UTC)"
        case .measurementEndpoints: "端点"
        case .measurementID: "計測 ID"
        case .sectionMission: "ミッション達成状況"
        case .missionUnavailable:
            "このキャプチャにはミッションプロファイル評価が記録されていません。"
        case .missionProfile: "タスクプロファイル"
        case .missionState: "評価状態"
        case .missionOverall: "必須項目すべて充足"
        case .missionUnsatisfied: "未充足の必須項目"
        case .missionRequirement: "要件"
        case .missionStatus: "状態"
        case .missionObserved: "観測数"
        case .sectionFindings: "所見と品質"
        case .qualityIntegrity: "整合性プリフライト"
        case .qualityRoomPlan: "RoomPlan 状態"
        case .missingAnnotations: "不足している必須注釈"
        case .missingMeasurements: "不足している必須計測"
        case .geometryDiscrepancy:
            "RoomPlan とメッシュの範囲に不一致の軸"
        case .conflictsUnavailable:
            "このキャプチャでは競合解析を実行できませんでした。"
        case .unreviewedOpenings: "件の開口候補が未レビュー"
        case .noFindings:
            "所見なし — 記録されたすべてのチェックをパスしました。"
        case .sectionEvidence: "証拠"
        case .evidenceFrames: "保持された証拠フレーム"
        case .depthFrames: "保持された深度ペイロード"
        case .noEvidenceSelected:
            "カメラ画像は含まれていません — プレビューは書き出し前に明示選択された場合のみ埋め込まれます。"
        case .evidenceSelectedNote:
            "以下のプレビューは明示的に選択されて含まれています。フル解像度フレームは .htdtcapture バンドル内にのみ残ります。"
        case .sectionProvenance: "来歴"
        case .sectionFieldNotes: "フィールドメモ"
        case .noFieldNotes:
            "このキャプチャではフィールドメモは記録されていません。"
        case .fieldNoteRecorded: "記録日時 (UTC)"
        case .fieldNoteNeedsAttention: "要注意"
        case .fieldNoteSeverity: "重要度"
        case .fieldNoteCategoryRoomCondition: "部屋の状況"
        case .fieldNoteCategoryObstruction: "障害物"
        case .fieldNoteCategoryEquipmentState: "機器の状態"
        case .fieldNoteCategoryGeometryCaveat: "ジオメトリ注意"
        case .fieldNoteCategoryMeasurementCaveat: "計測注意"
        case .fieldNoteCategoryFollowUp: "フォローアップ"
        case .fieldNoteCategoryInstallationObservation: "設置時の観察"
        case .fieldNoteCategoryGeneral: "一般"
        case .fieldNoteStatusActive: "未対応"
        case .fieldNoteStatusResolved: "対応済み"
        case .fieldNoteStatusSuperseded: "置き換え済み"
        case .fieldNoteSeverityObservation: "観察"
        case .fieldNoteSeverityConcern: "懸念"
        case .fieldNoteSeverityHazard: "危険"
        case .provenanceNote:
            "このドキュメントは上記の正確なキャプチャリビジョンとバンドルダイジェストから派生しています。すべてのソースペイロードはファイナライズ済みバンドルから読み取られました。"
        case .sourcePayloads: "ソースペイロード"
        case .reportExporter: "エクスポーター"
        case .unknown: "不明"
        case .yes: "はい"
        case .no: "いいえ"
        }
    }
}
