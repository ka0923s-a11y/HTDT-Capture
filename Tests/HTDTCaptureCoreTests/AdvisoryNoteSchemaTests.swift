import Foundation
import Testing
@testable import HTDTCaptureCore

/// legacy bolph71656-ai/HTDT-Capture#273: every `CaptureAdvisoryNoteKind` the app emits must validate
/// against the published `advisory-notes` schema — the v1.0.0 `kind`
/// enum previously lacked three already-emitted kinds
/// (`privacy_flag_cleared`, `roomplan_rescan`,
/// `roomplan_session_ended`), which would have failed bundle
/// validation for any capture carrying those notes.
@Test
func everyEmittedAdvisoryNoteKindValidatesAgainstSchema() throws {
    let schema = try CaptureBundleSchemaRegistry.compiledSchema(
        named: "advisory-notes"
    )
    let revisionID = CaptureRevisionID(
        rawValue: UUID(
            uuidString: "10000000-0000-4000-8000-00000000a010"
        )!
    )
    for kind in CaptureAdvisoryNoteKind.allCases {
        let document = CaptureAdvisoryNoteDocument(
            captureRevisionID: revisionID,
            notes: [
                CaptureAdvisoryNote(
                    kind: kind,
                    sessionTimestampSeconds: 1.0,
                    detail: "workload=test outcome=defer"
                ),
            ]
        )
        let payload = try StrictJSON.parse(document.encoded())
        let violation = JSONSchemaValidator.validate(
            payload,
            schema: schema
        )
        #expect(
            violation == nil,
            "kind \(kind.rawValue) must validate: \(String(describing: violation))"
        )
    }
}
