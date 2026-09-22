import XCTest
import HTDTCaptureCore
@testable import HTDTCaptureAppShell

/// Dynamic-review UX fixes: field-authority errors must reach the
/// operator as guidance (never a raw enum case), plan tokens seeded
/// into ledger titles must render localized/humanized names, and the
/// mission progress counts are localized format strings.
final class DynamicUXPresentationTests: XCTestCase {

    private func ledgerEntry(
        title: String,
        taskKind: HTDTFieldTaskKind?
    ) throws -> HTDTFieldReturnTaskLedgerEntry {
        try HTDTFieldReturnTaskLedgerEntry(
            itemRef: "task_item:item-1",
            title: title,
            requirement: .required,
            outcome: .unfulfilled,
            taskKind: taskKind
        )
    }

    // MARK: - FieldAuthorityModelError → errorText

    /// Every `FieldAuthorityModelError` case maps to operator
    /// guidance — the verbatim `String(describing:)` enum text the
    /// wiring form used to show is the defect this guards.
    func testFieldAuthorityModelErrorsNeverRenderVerbatim() {
        let errors: [FieldAuthorityModelError] = [
            .emptyField("title"),
            .invalidBindingRef("route:1"),
            .invalidToken("Speaker Wire"),
            .invalidTimestamp("noon"),
            .invalidCalendarDate("yesterday"),
            .duplicateRecord("route_id"),
            .unboundReference("evidence_refs"),
            .attestationRequired,
            .missingAssetAuthority,
            .invalidAssetPath("../x"),
            .invalidObservedValue,
            .invalidCalibrationWindow,
            .unknownInstrumentVersion,
            .endpointConflict,
            .hiddenPathGuess,
        ]
        for error in errors {
            let text = AnnotationPresentation.errorText(error)
            XCTAssertNotEqual(
                text, String(describing: error),
                "unmapped case: \(error)"
            )
            XCTAssertFalse(text.isEmpty)
        }
    }

    /// The reported defect: identical A/B endpoints rendered
    /// `endpointConflict` verbatim — now the operator sees the fix.
    func testEndpointConflictReadsAsGuidance() {
        XCTAssertEqual(
            AnnotationPresentation.errorText(
                FieldAuthorityModelError.endpointConflict
            ),
            "Each endpoint needs a distinct identity — bind it, "
                + "capture its position, or label it — and endpoints "
                + "A and B must differ."
        )
    }

    // MARK: - Ledger task titles

    /// A `quantity_type` token maps to its registered localized
    /// name rather than rendering raw.
    func testMeasurementTitleUsesQuantityName() throws {
        let entry = try ledgerEntry(
            title: "room_width", taskKind: .measurement
        )
        XCTAssertEqual(
            FieldReturnPresentation.taskTitle(entry), "Room width"
        )
        let open = try ledgerEntry(
            title: "floor_to_ceiling", taskKind: .measurement
        )
        XCTAssertEqual(
            FieldReturnPresentation.taskTitle(open),
            "floor to ceiling"
        )
    }

    /// `purpose` is a typed plan token (HTDTTaskPlanEvidenceItem):
    /// conventional tokens get localized names, unknown ones
    /// humanize, issuer free text renders verbatim.
    func testEvidencePurposeTitles() throws {
        XCTAssertEqual(
            FieldReturnPresentation.taskTitle(
                try ledgerEntry(
                    title: "equipment_label_photo",
                    taskKind: .evidenceTask
                )
            ),
            "Equipment label photo"
        )
        XCTAssertEqual(
            FieldReturnPresentation.taskTitle(
                try ledgerEntry(
                    title: "front_wall_photo",
                    taskKind: .evidenceTask
                )
            ),
            "front wall photo"
        )
        // Single-word issuer text is display text, not a token —
        // it stays exactly as issued.
        XCTAssertEqual(
            FieldReturnPresentation.taskTitle(
                try ledgerEntry(
                    title: "survey", taskKind: .evidenceTask
                )
            ),
            "survey"
        )
        XCTAssertEqual(
            FieldReturnPresentation.taskTitle(
                try ledgerEntry(
                    title: "Photo of the rack",
                    taskKind: .evidenceTask
                )
            ),
            "Photo of the rack"
        )
    }

    /// Entity/semantic rawValue fallbacks map to their localized
    /// names; a label hint renders verbatim.
    func testEntityAndSemanticTitles() throws {
        XCTAssertEqual(
            FieldReturnPresentation.taskTitle(
                try ledgerEntry(
                    title: "equipment_rack",
                    taskKind: .entityChecklist
                )
            ),
            "Equipment rack"
        )
        XCTAssertEqual(
            FieldReturnPresentation.taskTitle(
                try ledgerEntry(
                    title: "front_left speaker",
                    taskKind: .entityChecklist
                )
            ),
            "front_left speaker"
        )
        XCTAssertEqual(
            FieldReturnPresentation.taskTitle(
                try ledgerEntry(
                    title: "inventory_item",
                    taskKind: .otherSemantic
                )
            ),
            "Equipment item"
        )
        XCTAssertEqual(
            FieldReturnPresentation.taskTitle(
                try ledgerEntry(
                    title: "AVR rack", taskKind: .inventoryItem
                )
            ),
            "AVR rack"
        )
        // Legacy rows have no task kind — tokens still humanize.
        XCTAssertEqual(
            FieldReturnPresentation.taskTitle(
                try ledgerEntry(
                    title: "front_wall", taskKind: nil
                )
            ),
            "front wall"
        )
    }

    // MARK: - Mission progress

    func testKindProgressText() {
        XCTAssertEqual(
            MissionPresentation.kindProgressText(
                completedCount: 2,
                itemCount: 5,
                requiredOutstandingCount: 0
            ),
            "2/5 completed"
        )
        XCTAssertEqual(
            MissionPresentation.kindProgressText(
                completedCount: 2,
                itemCount: 5,
                requiredOutstandingCount: 3
            ),
            "2/5 completed · 3 required open"
        )
    }
}
