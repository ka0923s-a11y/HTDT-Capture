import Foundation
import SwiftUI
import HTDTCaptureCore

/// The spatial survey pass (issue #409): an object-first, state-
/// driven pass over every reviewable target — RoomPlan boundaries/
/// objects, mesh regions, committed entities — with the committed
/// records each one already holds. States are *derived*, never
/// authored: `notReviewed`/`partiallyDocumented`/`reviewed`/
/// `needsFollowUp`/`unavailable`/`unknown`/`notApplicable`, and the
/// distinction between "not yet visited" and "inspected and found
/// absent" is always kept.
///
/// This view never invents a parallel schema — it groups the
/// existing authority/evidence families onto the targets they bind
/// to, and nothing else. Modes filter which record families a
/// session pass cares about (construction / room-state /
/// equipment-installation) without hiding the targets.
public struct SpatialSurveyView: View {
    /// Rebuilds the survey for a mode; the model is derived, so a
    /// mode change is a re-derivation over the same committed set.
    public let makeModel: (SurveyMode) -> SpatialSurveyModel
    /// Read-only for finalized captures (issue #409 §13).
    public let readOnly: Bool

    @State private var mode: SurveyMode = .all

    public init(
        readOnly: Bool = true,
        makeModel: @escaping (SurveyMode) -> SpatialSurveyModel
    ) {
        self.readOnly = readOnly
        self.makeModel = makeModel
    }

    private var survey: SpatialSurveyModel {
        makeModel(mode)
    }

    public var body: some View {
        List {
            Section {
                Picker("Survey mode", selection: $mode) {
                    ForEach(SurveyMode.allCases, id: \.self) {
                        Text(
                            SpatialSurveyPresentation
                                .modeName($0)
                        )
                        .tag($0)
                    }
                }
                .pickerStyle(.segmented)
                Text(
                    SpatialSurveyPresentation
                        .modeDescription(mode)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } footer: {
                Text(
                    "States are derived from committed records — this list never edits authorities."
                )
            }

            Section("Progress") {
                let summary = survey.summary
                LabeledContent(
                    "Reviewed",
                    value:
                        SpatialSurveyPresentation
                            .reviewedProgressText(
                                reviewedCount: summary.reviewedCount,
                                totalCount: summary.totalCount
                            )
                )
                if summary.missionRequiredGapCount > 0 {
                    LabeledContent(
                        "Required gaps",
                        value: captureCountPhrase(
                            summary.missionRequiredGapCount,
                            singular: String(
                                localized: "%lld target"
                            ),
                            plural: String(
                                localized: "%lld targets"
                            )
                        )
                    )
                    .foregroundStyle(CaptureColorRole.attention.color)
                }
                LabeledContent(
                    "Remaining",
                    value: "\(summary.remainingCount)"
                )
            }

            if !survey.nextUnresolved.isEmpty {
                Section {
                    ForEach(survey.nextUnresolved.prefix(15)) {
                        entry in
                        NavigationLink {
                            SpatialSurveyTargetView(
                                entry: entry,
                                readOnly: readOnly
                            )
                        } label: {
                            entryRow(entry)
                        }
                    }
                } header: {
                    Text("Next unresolved")
                } footer: {
                    Text(
                        "Mission-required targets first, then attention flags, then boundaries, then objects."
                    )
                }
            }

            ForEach(SurveyTargetClass.allCases, id: \.self) {
                targetClass in
                let entries = survey.entries.filter {
                    $0.target.targetClass == targetClass
                }
                if !entries.isEmpty {
                    Section(
                        SpatialSurveyPresentation.className(
                            targetClass
                        )
                    ) {
                        ForEach(entries) { entry in
                            NavigationLink {
                                SpatialSurveyTargetView(
                                    entry: entry,
                                    readOnly: readOnly
                                )
                            } label: {
                                entryRow(entry)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Spatial survey")
    }

    private func entryRow(
        _ entry: SurveyTargetEntry
    ) -> some View {
        HStack(spacing: 10) {
            Image(
                systemName: SpatialSurveyPresentation
                    .stateSymbol(entry.state)
            )
            .foregroundStyle(
                SpatialSurveyPresentation.stateColor(
                    entry.state
                )
            )
            .accessibilityLabel(
                SpatialSurveyPresentation.stateName(
                    entry.state
                )
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.target.label)
                    .font(.callout)
                Text(
                    [
                        SpatialSurveyPresentation.kindName(
                            entry.target.kind
                        ),
                        entry.attentionReasons.first,
                    ]
                    .compactMap { $0 }
                    .joined(separator: " — ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            Spacer()
            if entry.target.isMissionRequired,
               !entry.pendingMissionItemIDs.isEmpty
            {
                Text("Required")
                    .font(.caption2)
                    .foregroundStyle(CaptureColorRole.attention.color)
            }
        }
    }
}

/// One survey target's object-first detail (issue #409 §5): only the
/// record families actually present render — an object with no
/// commissioning record never shows an empty commissioning block.
public struct SpatialSurveyTargetView: View {
    public let entry: SurveyTargetEntry
    public let readOnly: Bool

    public init(
        entry: SurveyTargetEntry,
        readOnly: Bool
    ) {
        self.entry = entry
        self.readOnly = readOnly
    }

    public var body: some View {
        List {
            Section {
                LabeledContent(
                    "Kind",
                    value: SpatialSurveyPresentation
                        .kindName(entry.target.kind)
                )
                LabeledContent(
                    "State",
                    value: SpatialSurveyPresentation
                        .stateName(entry.state)
                )
                if readOnly {
                    Text("Finalized capture — records are read-only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !entry.target.matchTokens.isEmpty {
                    CaptureTechnicalDetail(
                        "Bindings",
                        value: entry.target.matchTokens
                            .sorted().joined(separator: ", ")
                    )
                }
            }

            if !entry.pendingMissionItemIDs.isEmpty {
                Section("Mission items") {
                    ForEach(
                        entry.pendingMissionItemIDs,
                        id: \.self
                    ) { item in
                        Text(item)
                            .font(.caption.monospaced())
                    }
                }
            }

            if !entry.attentionReasons.isEmpty {
                Section("Attention") {
                    ForEach(
                        entry.attentionReasons,
                        id: \.self
                    ) { reason in
                        Label(
                            reason,
                            systemImage:
                                "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(CaptureColorRole.attention.color)
                    }
                }
            }

            // Missing-but-expected families explain the state —
            // e.g. a wall with construction but no room-state record
            // is `partiallyDocumented`, never silently "done".
            let missing = entry.expectedFamilies
                .subtracting(entry.presentFamilies)
                .sorted { $0.rawValue < $1.rawValue }
            if !missing.isEmpty {
                Section("Not yet documented") {
                    ForEach(missing, id: \.self) { family in
                        Label(
                            SpatialSurveyPresentation
                                .familyName(family),
                            systemImage: "circle.dashed"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(
                SurveyRecordFamily.allCases,
                id: \.self
            ) { family in
                let records = entry.records.filter {
                    $0.family == family
                }
                if !records.isEmpty {
                    Section(
                        SpatialSurveyPresentation
                            .familyName(family)
                    ) {
                        ForEach(records) { record in
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(record.recordID)
                                    .font(.caption.monospaced())
                                if !record.evidenceRefs.isEmpty {
                                    Text(
                                        captureCountPhrase(
                                            record.evidenceRefs.count,
                                            singular: String(
                                                localized: "%lld evidence reference"
                                            ),
                                            plural: String(
                                                localized: "%lld evidence references"
                                            )
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(entry.target.label)
    }
}

/// Names, colors, and symbols shared by survey rows and details so
/// state language never drifts between the list and the detail.
public enum SpatialSurveyPresentation {
    public static func modeName(_ mode: SurveyMode) -> String {
        switch mode {
        case .all:
            return String(localized: "All")
        case .construction:
            return String(localized: "Construction")
        case .roomState:
            return String(localized: "Room state")
        case .equipmentInstallation:
            return String(localized: "Equipment")
        }
    }

    /// "Reviewed" value in the Progress section.
    public static func reviewedProgressText(
        reviewedCount: Int,
        totalCount: Int
    ) -> String {
        String(
            format: String(localized: "%lld of %lld"),
            reviewedCount,
            totalCount
        )
    }

    /// Caption under the mode picker — which records each filter
    /// shows.
    public static func modeDescription(_ mode: SurveyMode) -> String {
        switch mode {
        case .all:
            return String(localized:
                "Shows every survey record.")
        case .construction:
            return String(localized:
                "Only construction records — openings, structure.")
        case .roomState:
            return String(localized:
                "Only variable room-state records — curtains, doors, seating.")
        case .equipmentInstallation:
            return String(localized:
                "Only equipment-installation records.")
        }
    }

    public static func stateName(
        _ state: SurveyRecordState
    ) -> String {
        switch state {
        case .notReviewed:
            return String(localized: "Not reviewed")
        case .partiallyDocumented:
            return String(localized: "Partially documented")
        case .reviewed:
            return String(localized: "Reviewed")
        case .needsFollowUp:
            return String(localized: "Needs follow-up")
        case .unavailable:
            return String(localized: "Unavailable")
        case .unknown:
            return String(localized: "Unknown")
        case .notApplicable:
            return String(localized: "Not applicable")
        }
    }

    public static func stateColor(
        _ state: SurveyRecordState
    ) -> Color {
        switch state {
        case .reviewed:
            return .green
        case .partiallyDocumented:
            return .teal
        case .notReviewed:
            return .secondary
        case .needsFollowUp:
            return .orange
        case .unavailable, .unknown:
            return .secondary
        case .notApplicable:
            return .secondary.opacity(0.6)
        }
    }

    public static func stateSymbol(
        _ state: SurveyRecordState
    ) -> String {
        switch state {
        case .reviewed:
            return "checkmark.circle.fill"
        case .partiallyDocumented:
            return "circle.lefthalf.filled"
        case .notReviewed:
            return "circle"
        case .needsFollowUp:
            return "exclamationmark.circle.fill"
        case .unavailable:
            return "nosign"
        case .unknown:
            return "questionmark.circle"
        case .notApplicable:
            return "minus.circle"
        }
    }

    public static func className(
        _ targetClass: SurveyTargetClass
    ) -> String {
        switch targetClass {
        case .roomBoundary:
            return String(localized: "Room boundaries")
        case .opening:
            return String(localized: "Openings")
        case .roomObject:
            return String(localized: "Objects")
        case .semanticEntity:
            return String(localized: "Committed entities")
        case .feature:
            return String(localized: "Features")
        case .room:
            return String(localized: "Room")
        }
    }

    public static func kindName(
        _ kind: SurveyTargetKind
    ) -> String {
        switch kind {
        case .room:
            return String(localized: "Room")
        case .wall:
            return String(localized: "Wall")
        case .floor:
            return String(localized: "Floor")
        case .door:
            return String(localized: "Door")
        case .window:
            return String(localized: "Window")
        case .opening:
            return String(localized: "Opening")
        case .object:
            return String(localized: "Object")
        case .speaker:
            return String(localized: "Speaker")
        case .seat:
            return String(localized: "Seat")
        case .screen:
            return String(localized: "Screen")
        case .projector:
            return String(localized: "Projector")
        case .display:
            return String(localized: "Display")
        case .genericEntity:
            return String(localized: "Entity")
        case .meshRegion:
            return String(localized: "Mesh region")
        }
    }

    public static func familyName(
        _ family: SurveyRecordFamily
    ) -> String {
        switch family {
        case .surfaceIdentity:
            return String(localized: "Surface identity")
        case .construction:
            return String(localized: "Construction")
        case .constructionFeature:
            return String(localized: "Construction features")
        case .problemSurface:
            return String(localized: "Problem surfaces")
        case .roomState:
            return String(localized: "Room state")
        case .furnitureSemantics:
            return String(localized: "Furniture")
        case .equipmentInventory:
            return String(localized: "Equipment")
        case .installation:
            return String(localized: "Installations")
        case .commissioning:
            return String(localized: "Commissioning")
        case .wiring:
            return String(localized: "Wiring")
        case .measurement:
            return String(localized: "Measurements")
        case .fieldEvidence:
            return String(localized: "Field evidence")
        }
    }
}
