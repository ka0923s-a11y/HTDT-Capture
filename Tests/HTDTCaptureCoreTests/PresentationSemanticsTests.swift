import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issues #360–#364: the shared presentation vocabulary and the pure
/// composition rules behind the GUI redesign stay in Core so the
/// information hierarchy is verifiable without rendering SwiftUI.
final class PresentationSemanticsTests: XCTestCase {

    // MARK: - CaptureSemanticStatus (#361)

    func testEveryStatusHasLabelSymbolAndColor() {
        for status in CaptureSemanticStatus.allCases {
            XCTAssertFalse(
                status.labelKey.isEmpty,
                "\(status) has no label"
            )
            XCTAssertFalse(
                status.symbolName.isEmpty,
                "\(status) has no symbol — status must never be color-only"
            )
        }
    }

    func testStatusColorRolesFollowTheFrozenVocabulary() {
        XCTAssertEqual(
            CaptureSemanticStatus.ready.colorRole, .success
        )
        XCTAssertEqual(
            CaptureSemanticStatus.verified.colorRole, .success
        )
        XCTAssertEqual(
            CaptureSemanticStatus.blocked.colorRole, .blocked
        )
        XCTAssertEqual(
            CaptureSemanticStatus.needsReview.colorRole, .attention
        )
        XCTAssertEqual(
            CaptureSemanticStatus.advisory.colorRole, .attention
        )
        XCTAssertEqual(
            CaptureSemanticStatus.pending.colorRole, .attention
        )
        XCTAssertEqual(
            CaptureSemanticStatus.incomplete.colorRole, .attention
        )
        XCTAssertEqual(
            CaptureSemanticStatus.draft.colorRole, .attention
        )
        XCTAssertEqual(
            CaptureSemanticStatus.unavailable.colorRole, .unknown
        )
        XCTAssertEqual(
            CaptureSemanticStatus.unknown.colorRole, .unknown
        )
        XCTAssertEqual(
            CaptureSemanticStatus.finalized.colorRole, .accent
        )
        XCTAssertEqual(
            CaptureSemanticStatus.imported.colorRole, .informational
        )
        XCTAssertEqual(
            CaptureSemanticStatus.derived.colorRole, .derived
        )
        XCTAssertEqual(
            CaptureSemanticStatus.skipped.colorRole, .secondary
        )
    }

    // MARK: - CaptureHomePresentation (#360)

    func testNoticesOrderedByOperatorAction() {
        let notices = CaptureHomePresentation.notices(
            cameraPermissionDenied: true,
            cameraPermissionRestricted: false,
            deviceCaptureEligible: false,
            storageReadiness: .critical,
            maintenanceItemCount: 2
        )
        XCTAssertEqual(
            notices,
            [
                .cameraAccessRequired,
                .deviceUnsupported,
                .storageCritical,
                .libraryMaintenance(itemCount: 2),
            ]
        )
    }

    func testRestrictedCameraAlsoRaisesAccessNotice() {
        let notices = CaptureHomePresentation.notices(
            cameraPermissionDenied: false,
            cameraPermissionRestricted: true,
            deviceCaptureEligible: true,
            storageReadiness: .sufficient,
            maintenanceItemCount: 0
        )
        XCTAssertEqual(notices, [.cameraAccessRequired])
    }

    func testHealthyDeviceShowsNoNotices() {
        let notices = CaptureHomePresentation.notices(
            cameraPermissionDenied: false,
            cameraPermissionRestricted: false,
            deviceCaptureEligible: true,
            storageReadiness: .sufficient,
            maintenanceItemCount: 0
        )
        XCTAssertTrue(notices.isEmpty)
    }

    func testLowStorageIsAdvisoryNotBlockingNotice() {
        let notices = CaptureHomePresentation.notices(
            cameraPermissionDenied: false,
            cameraPermissionRestricted: false,
            deviceCaptureEligible: true,
            storageReadiness: .low,
            maintenanceItemCount: 0
        )
        XCTAssertTrue(notices.isEmpty)
    }

    func testMaintenanceItemCountSumsAllBuckets() {
        let quarantine = PersistedCaptureQuarantinedArtifact(
            kind: .unexpectedItem,
            url: URL(fileURLWithPath: "/tmp/q"),
            reason: "test"
        )
        let orphan = PersistedCaptureWorkingOrphan(
            kind: .staleWriterTempFile,
            url: URL(fileURLWithPath: "/tmp/o"),
            retainedBytes: 1
        )
        let inventory = PersistedCaptureInventoryResult(
            quarantinedArtifacts: [quarantine],
            orphanedWorkingArtifacts: [orphan],
            enumerationFailures: ["a", "b"]
        )
        XCTAssertEqual(
            CaptureHomePresentation.maintenanceItemCount(inventory),
            4
        )
    }

    // MARK: - CaptureAdaptiveLayoutDecision (#362)

    func testRegularWidthPrefersPanes() {
        XCTAssertTrue(
            CaptureAdaptiveLayoutDecision.prefersPanes(
                isRegularWidthClass: true,
                availableWidth: 1024,
                isAccessibilityDynamicType: false
            )
        )
    }

    func testCompactNarrowStaysSingleColumn() {
        XCTAssertFalse(
            CaptureAdaptiveLayoutDecision.prefersPanes(
                isRegularWidthClass: false,
                availableWidth: 375,
                isAccessibilityDynamicType: false
            )
        )
    }

    func testWideWithoutSizeClassUsesAvailableWidth() {
        XCTAssertTrue(
            CaptureAdaptiveLayoutDecision.prefersPanes(
                isRegularWidthClass: false,
                availableWidth: 700,
                isAccessibilityDynamicType: false
            )
        )
        XCTAssertFalse(
            CaptureAdaptiveLayoutDecision.prefersPanes(
                isRegularWidthClass: false,
                availableWidth: 699,
                isAccessibilityDynamicType: false
            )
        )
    }

    func testAccessibilityDynamicTypeFallsBackToSingleColumn() {
        XCTAssertFalse(
            CaptureAdaptiveLayoutDecision.prefersPanes(
                isRegularWidthClass: true,
                availableWidth: 1180,
                isAccessibilityDynamicType: true
            )
        )
    }

    // MARK: - CaptureSeriesPresentation (#360)

    private func record(
        canOpen: Bool = true,
        finalizedAt: String = "2026-09-22T00:00:00Z",
        previewPaths: [String] = []
    ) throws -> PersistedCaptureRecord {
        var validation: BundleValidationReport?
        if canOpen || !previewPaths.isEmpty {
            let revisionID = CaptureRevisionID()
            let entries = try previewPaths.map {
                try BundleValidationFixture.entry(
                    path: $0,
                    data: Data(),
                    mediaType: "image/heic"
                )
            }
            let manifest = try BundleManifest(
                captureSeriesID: CaptureSeriesID(),
                captureRevisionID: revisionID,
                parentRevisionID: nil,
                captureSessionIDs: [CaptureSessionID()],
                coordinateSpaceIDs: [CoordinateSpaceID()],
                createdAtUTC: finalizedAt,
                finalizedAtUTC: finalizedAt,
                app: BundleAppIdentity(
                    version: "test",
                    build: "test"
                ),
                files: entries
            )
            validation = try BundleValidationReport(
                manifest: manifest,
                bundleDigest: EvidenceSHA256(
                    "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
                ),
                payloadCount: 0
            )
        }
        return PersistedCaptureRecord(
            captureRevisionID: CaptureRevisionID(
                rawValue: UUID()
            ),
            captureSeriesID: CaptureSeriesID(rawValue: UUID()),
            finalizedAtUTC: finalizedAt,
            finalizedDirectory: canOpen
                ? URL(fileURLWithPath: "/tmp/finalized") : nil,
            finalizedValidation: canOpen ? validation : nil,
            exportArchive: canOpen
                ? nil
                : URL(fileURLWithPath: "/tmp/archive.htdtcapture"),
            exportValidation: canOpen ? nil : validation,
            finalizedByteCount: canOpen ? 100 : nil,
            exportArchiveByteCount: canOpen ? nil : 50
        )
    }

    private func group(
        revisions: [PersistedCaptureRecord],
        metadata: CaptureLibraryEntryMetadata? = nil
    ) -> CaptureSeriesGroup {
        CaptureSeriesGroup(
            captureSeriesID: CaptureSeriesID(rawValue: UUID()),
            revisions: revisions,
            metadata: metadata
        )
    }

    func testStatusForFinalizedImportedAndMissing() throws {
        XCTAssertEqual(
            CaptureSeriesPresentation.status(
                for: try record(canOpen: true)
            ),
            .finalized
        )
        XCTAssertEqual(
            CaptureSeriesPresentation.status(
                for: try record(canOpen: false)
            ),
            .imported
        )
        XCTAssertEqual(
            CaptureSeriesPresentation.status(for: nil),
            .unknown
        )
    }

    func testNamedSeriesUsesOperatorName() throws {
        let presentation = CaptureSeriesPresentation(
            group: group(
                revisions: [try record()],
                metadata: CaptureLibraryEntryMetadata(
                    displayName: "Living room"
                )
            ),
            revisionMetadata: nil,
            locale: Locale(identifier: "en_US_POSIX")
        )
        XCTAssertEqual(presentation.title, "Living room")
        XCTAssertTrue(presentation.isNamed)
    }

    func testUnnamedSeriesNeverFallsBackToRawUUID() throws {
        let presentation = CaptureSeriesPresentation(
            group: group(revisions: [try record()]),
            revisionMetadata: nil,
            locale: Locale(identifier: "en_US_POSIX")
        )
        XCTAssertFalse(presentation.isNamed)
        XCTAssertFalse(presentation.title.isEmpty)
        XCTAssertNil(UUID(uuidString: presentation.title))
    }

    func testRevisionSummarySingularAndPlural() throws {
        let one = CaptureSeriesPresentation(
            group: group(revisions: [try record()]),
            revisionMetadata: nil
        )
        XCTAssertEqual(one.revisionSummary, "1 revision")
        let three = CaptureSeriesPresentation(
            group: group(
                revisions: [try record(), try record(), try record()]
            ),
            revisionMetadata: nil
        )
        XCTAssertEqual(three.revisionSummary, "3 revisions")
    }

    // MARK: - Series representative previews (#411)

    /// The deterministic policy: latest revision first, then the most
    /// recent revision in the series that still declares a preview;
    /// revisions without manifest-declared previews are skipped; an
    /// empty result is what drives the semantic placeholder.
    func testRepresentativePreviewCandidatesOrderAndFilter() throws {
        let previewPath = "evidence/frames/f1.preview.heic"
        let oldest = try record(
            finalizedAt: "2026-09-18T00:00:00Z",
            previewPaths: [previewPath]
        )
        let noPreview = try record(finalizedAt: "2026-09-19T00:00:00Z")
        let newest = try record(
            finalizedAt: "2026-09-20T00:00:00Z",
            previewPaths: [previewPath]
        )
        let candidates = group(
            revisions: [oldest, noPreview, newest]
        ).representativePreviewCandidates
        XCTAssertEqual(
            candidates.map(\.captureRevisionID),
            [newest, oldest].map(\.captureRevisionID)
        )
        XCTAssertTrue(
            group(revisions: [noPreview])
                .representativePreviewCandidates
                .isEmpty
        )
    }

    /// An archive-only (imported/export-only) record whose export
    /// manifest declares a preview counts exactly like a finalized
    /// one — provenance never changes the thumbnail policy.
    func testRepresentativePreviewCandidatesTreatArchiveOnlyIdentically()
        throws
    {
        let previewPath = "evidence/frames/f1.preview.heic"
        let archiveOnly = try record(
            canOpen: false,
            finalizedAt: "2026-09-19T00:00:00Z",
            previewPaths: [previewPath]
        )
        let candidates = group(
            revisions: [archiveOnly]
        ).representativePreviewCandidates
        XCTAssertEqual(
            candidates.map(\.captureRevisionID),
            [archiveOnly.captureRevisionID]
        )
    }

    func testDateLabelParsesCanonicalUTC() {
        // Midday UTC keeps the calendar day identical across the
        // developer-machines' plausible local timezones.
        let label = CaptureSeriesPresentation.dateLabel(
            for: "2026-09-22T12:00:00Z",
            locale: Locale(identifier: "en_US_POSIX")
        )
        XCTAssertEqual(label, "Sep 22, 2026")
    }

    func testDateLabelParsesFractionalSeconds() {
        XCTAssertNotNil(
            CaptureSeriesPresentation.dateLabel(
                for: "2026-09-22T00:00:00.123Z",
                locale: Locale(identifier: "en_US_POSIX")
            )
        )
    }

    func testDateLabelRejectsGarbage() {
        XCTAssertNil(
            CaptureSeriesPresentation.dateLabel(for: "not-a-date")
        )
        XCTAssertNil(CaptureSeriesPresentation.dateLabel(for: nil))
        XCTAssertNil(CaptureSeriesPresentation.dateLabel(for: ""))
    }
}
