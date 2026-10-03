import Foundation

/// UI-facing model of a long-running host operation (legacy bolph71656-ai/HTDT-Capture#309).
///
/// The coordinator guards conflicting work with private in-flight
/// flags; `activeOperations` publishes the same information so views
/// can disable the controls whose taps would be silently ignored and
/// show immediate progress feedback instead of appearing frozen.
/// Persisted-library rows additionally match
/// `CaptureRootView.operationTargetRevisionID` to show which entry an
/// open/delete operates on.
public enum CaptureHostOperation: String, Sendable, Equatable, Hashable {
    /// `.htdtcapture` archive import from Files/`openURL`.
    case importArchive = "import_archive"
    /// Revalidation/open of a persisted library entry or working
    /// revision into the persisted workspace.
    case openPersisted = "open_persisted"
    /// Local deletion of a persisted library entry or orphan.
    case deletePersisted = "delete_persisted"
    /// Archive creation/validation after End (`prepareExport`).
    case prepareExport = "prepare_export"
    /// Post-capture review/finalization pipeline
    /// (`reviewOperationInFlight`).
    case reviewOperation = "review_operation"
    /// Annotation-authority commit
    /// (`annotationCommitInFlight`).
    case annotationCommit = "annotation_commit"
    /// Diagnostic package export from the failed state.
    case exportDiagnostics = "export_diagnostics"
    /// Semantic-child revision build (legacy bolph71656-ai/HTDT-Capture#319): stages the child under
    /// `working/`, so the library must stay busy while it is in
    /// flight or the inventory classifies the staged bytes as an
    /// orphan.
    case semanticCorrection = "semantic_correction"
}
