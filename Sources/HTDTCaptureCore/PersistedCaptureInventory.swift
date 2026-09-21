import Foundation

/// Errors raised by the persisted-capture inventory authority.
public enum PersistedCaptureInventoryError:
    Error,
    Sendable,
    Equatable
{
    /// The artifact did not resolve to a direct child of one of the
    /// app-owned capture roots, so removing it was refused.
    case unsafeArtifactLocation
}

/// Classifies a filesystem item that lives under an app-owned capture
/// root but could not be adopted as validated capture authority.
public enum PersistedCaptureArtifactKind:
    String,
    Sendable,
    Equatable
{
    /// A direct child directory of `finalized/`.
    case finalizedDirectory
    /// A `.htdtcapture` file inside `exports/`.
    case exportArchive
    /// Any other item: stray files, partial temporary output, symbolic
    /// links, or directories where an archive file is expected.
    case unexpectedItem
}

/// A filesystem item inside the app-owned capture roots that failed
/// validation or does not occupy the canonical location of its manifest
/// identity. Quarantined artifacts are reported to the user, never
/// silently adopted.
public struct PersistedCaptureQuarantinedArtifact:
    Sendable,
    Equatable,
    Identifiable
{
    public let kind: PersistedCaptureArtifactKind
    public let url: URL
    /// Deterministic diagnostic text explaining why the artifact was not
    /// adopted.
    public let reason: String

    public init(
        kind: PersistedCaptureArtifactKind,
        url: URL,
        reason: String
    ) {
        self.kind = kind
        self.url = url
        self.reason = reason
    }

    public var id: URL { url }
}

/// A validated persisted capture. Identity always comes from the
/// validated manifest, never from a directory or file name.
public struct PersistedCaptureRecord:
    Sendable,
    Equatable,
    Identifiable
{
    public let captureRevisionID: CaptureRevisionID
    public let captureSeriesID: CaptureSeriesID
    public let finalizedAtUTC: String
    /// The validated `finalized/<capture_revision_id>` directory, or nil
    /// when only a validated export archive remains on disk.
    public let finalizedDirectory: URL?
    public let finalizedValidation: BundleValidationReport?
    /// The validated `exports/<capture_revision_id>.htdtcapture`
    /// archive. When the finalized directory is also present the
    /// archive's bundle digest was proven identical at scan time.
    public let exportArchive: URL?
    public let exportValidation: BundleValidationReport?

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSeriesID: CaptureSeriesID,
        finalizedAtUTC: String,
        finalizedDirectory: URL?,
        finalizedValidation: BundleValidationReport?,
        exportArchive: URL?,
        exportValidation: BundleValidationReport?
    ) {
        self.captureRevisionID = captureRevisionID
        self.captureSeriesID = captureSeriesID
        self.finalizedAtUTC = finalizedAtUTC
        self.finalizedDirectory = finalizedDirectory
        self.finalizedValidation = finalizedValidation
        self.exportArchive = exportArchive
        self.exportValidation = exportValidation
    }

    public var id: CaptureRevisionID {
        captureRevisionID
    }

    /// Only a record that still carries a validated finalized bundle can
    /// be adopted as the host's current finalized revision.
    public var canOpen: Bool {
        finalizedDirectory != nil && finalizedValidation != nil
    }
}

/// An artifact that could not be removed during a deletion transaction,
/// together with the precise reason it stayed on disk.
public struct PersistedCaptureRemainingArtifact:
    Sendable,
    Equatable
{
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

/// The exact outcome of a delete-local-capture transaction. A partial
/// result never reports success: anything left on disk is listed in
/// `remaining` with the reason it stayed.
public struct PersistedCaptureDeletionResult:
    Sendable,
    Equatable
{
    public let captureRevisionID: CaptureRevisionID
    public let removed: [URL]
    public let remaining: [PersistedCaptureRemainingArtifact]

    public init(
        captureRevisionID: CaptureRevisionID,
        removed: [URL],
        remaining: [PersistedCaptureRemainingArtifact]
    ) {
        self.captureRevisionID = captureRevisionID
        self.removed = removed
        self.remaining = remaining
    }

    public var succeeded: Bool {
        remaining.isEmpty
    }
}

/// The outcome of one deterministic scan of the app-owned capture
/// roots: validated captures, quarantined artifacts, and root-level
/// enumeration failures.
public struct PersistedCaptureInventoryResult:
    Sendable,
    Equatable
{
    public let captures: [PersistedCaptureRecord]
    public let quarantinedArtifacts:
        [PersistedCaptureQuarantinedArtifact]
    public let enumerationFailures: [String]

    public init(
        captures: [PersistedCaptureRecord] = [],
        quarantinedArtifacts:
            [PersistedCaptureQuarantinedArtifact] = [],
        enumerationFailures: [String] = []
    ) {
        self.captures = captures
        self.quarantinedArtifacts = quarantinedArtifacts
        self.enumerationFailures = enumerationFailures
    }

    public var isEmpty: Bool {
        captures.isEmpty
            && quarantinedArtifacts.isEmpty
            && enumerationFailures.isEmpty
    }
}

/// Deterministic inventory and deletion authority for the app-owned
/// persisted capture roots:
///
///     <captureRoot>/finalized/<capture_revision_id>/
///     <captureRoot>/exports/<capture_revision_id>.htdtcapture
///
/// Every candidate is validated with the same validators the capture
/// pipeline uses (`BundleDirectoryValidator` for directories,
/// `StoredCaptureBundleArchiveValidator` for stored archives). Revision
/// identity always comes from the validated manifest; directory and
/// file names only decide whether an artifact occupies its canonical
/// slot. This type never resurrects `working/` scans: an interrupted
/// scan leaves no live AR coordinate authority to resume into.
public struct PersistedCaptureInventory: Sendable {
    public let finalizedRoot: URL
    public let exportsRoot: URL
    public let limits: BundleFilesystemLimits

    public init(
        captureRoot: URL,
        limits: BundleFilesystemLimits = .init()
    ) {
        self.init(
            finalizedRoot: captureRoot.appendingPathComponent(
                "finalized",
                isDirectory: true
            ),
            exportsRoot: captureRoot.appendingPathComponent(
                "exports",
                isDirectory: true
            ),
            limits: limits
        )
    }

    public init(
        finalizedRoot: URL,
        exportsRoot: URL,
        limits: BundleFilesystemLimits = .init()
    ) {
        self.finalizedRoot = finalizedRoot
        self.exportsRoot = exportsRoot
        self.limits = limits
    }

    /// Enumerates both capture roots and validates every candidate.
    /// A validated finalized directory becomes a record; a validated
    /// archive joins the record of the same manifest revision when its
    /// bundle digest matches, or forms an export-only record when no
    /// finalized directory exists. Anything else is quarantined with a
    /// precise reason instead of being adopted.
    public func scan() -> PersistedCaptureInventoryResult {
        var captures: [CaptureRevisionID: PersistedCaptureRecord] = [:]
        var order: [CaptureRevisionID] = []
        var quarantined:
            [PersistedCaptureQuarantinedArtifact] = []
        var enumerationFailures: [String] = []

        for child in children(
            of: finalizedRoot,
            failures: &enumerationFailures
        ) {
            switch childKind(child) {
            case .directory:
                let report: BundleValidationReport
                do {
                    report = try BundleDirectoryValidator.validate(
                        root: child,
                        limits: limits
                    )
                } catch {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .finalizedDirectory,
                            url: child,
                            reason:
                                "finalized bundle validation failed: "
                                + Self.diagnostic(error)
                        )
                    )
                    continue
                }

                let revisionID =
                    report.manifest.captureRevisionID
                guard child.lastPathComponent
                        == revisionID.description
                else {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .finalizedDirectory,
                            url: child,
                            reason:
                                "validated manifest revision "
                                + revisionID.description
                                + " is stored under a non-canonical directory name"
                        )
                    )
                    continue
                }
                guard captures[revisionID] == nil else {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .finalizedDirectory,
                            url: child,
                            reason:
                                "duplicate finalized revision "
                                + revisionID.description
                        )
                    )
                    continue
                }

                captures[revisionID] = PersistedCaptureRecord(
                    captureRevisionID: revisionID,
                    captureSeriesID:
                        report.manifest.captureSeriesID,
                    finalizedAtUTC:
                        report.manifest.finalizedAtUTC,
                    finalizedDirectory: finalizedDirectory(
                        for: revisionID
                    ),
                    finalizedValidation: report,
                    exportArchive: nil,
                    exportValidation: nil
                )
                order.append(revisionID)

            case .symbolicLink:
                quarantined.append(
                    PersistedCaptureQuarantinedArtifact(
                        kind: .unexpectedItem,
                        url: child,
                        reason:
                            "symbolic-link entries are never adopted"
                    )
                )
            case .regularFile, .other, .unreadable:
                quarantined.append(
                    PersistedCaptureQuarantinedArtifact(
                        kind: .unexpectedItem,
                        url: child,
                        reason:
                            "not a finalized revision directory"
                    )
                )
            }
        }

        for child in children(
            of: exportsRoot,
            failures: &enumerationFailures
        ) {
            switch childKind(child) {
            case .regularFile:
                guard child.pathExtension == "htdtcapture"
                else {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .unexpectedItem,
                            url: child,
                            reason:
                                "unrecognized item inside the exports root"
                        )
                    )
                    continue
                }

                let report: BundleValidationReport
                do {
                    report =
                        try StoredCaptureBundleArchiveValidator
                            .validate(
                                archive: child,
                                limits: limits
                            )
                } catch {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .exportArchive,
                            url: child,
                            reason:
                                "export archive validation failed: "
                                + Self.diagnostic(error)
                        )
                    )
                    continue
                }

                let revisionID =
                    report.manifest.captureRevisionID
                guard child.lastPathComponent
                        == revisionID.description
                            + ".htdtcapture"
                else {
                    quarantined.append(
                        PersistedCaptureQuarantinedArtifact(
                            kind: .exportArchive,
                            url: child,
                            reason:
                                "validated manifest revision "
                                + revisionID.description
                                + " is stored under a non-canonical archive name"
                        )
                    )
                    continue
                }

                if let existing = captures[revisionID] {
                    guard existing.finalizedValidation?
                        .bundleDigest == report.bundleDigest
                    else {
                        quarantined.append(
                            PersistedCaptureQuarantinedArtifact(
                                kind: .exportArchive,
                                url: child,
                                reason:
                                    "archive bundle digest does not match the finalized revision"
                            )
                        )
                        continue
                    }
                    captures[revisionID] =
                        PersistedCaptureRecord(
                            captureRevisionID:
                                existing.captureRevisionID,
                            captureSeriesID:
                                existing.captureSeriesID,
                            finalizedAtUTC:
                                existing.finalizedAtUTC,
                            finalizedDirectory:
                                existing.finalizedDirectory,
                            finalizedValidation:
                                existing.finalizedValidation,
                            exportArchive: exportArchiveURL(
                                for: revisionID
                            ),
                            exportValidation: report
                        )
                } else {
                    captures[revisionID] =
                        PersistedCaptureRecord(
                            captureRevisionID: revisionID,
                            captureSeriesID:
                                report.manifest
                                    .captureSeriesID,
                            finalizedAtUTC:
                                report.manifest
                                    .finalizedAtUTC,
                            finalizedDirectory: nil,
                            finalizedValidation: nil,
                            exportArchive: exportArchiveURL(
                                for: revisionID
                            ),
                            exportValidation: report
                        )
                    order.append(revisionID)
                }

            case .symbolicLink:
                quarantined.append(
                    PersistedCaptureQuarantinedArtifact(
                        kind: .unexpectedItem,
                        url: child,
                        reason:
                            "symbolic-link entries are never adopted"
                    )
                )
            case .directory, .other, .unreadable:
                quarantined.append(
                    PersistedCaptureQuarantinedArtifact(
                        kind: .unexpectedItem,
                        url: child,
                        reason:
                            "not an export archive file"
                    )
                )
            }
        }

        let sorted = order
            .compactMap { captures[$0] }
            .sorted { lhs, rhs in
                if lhs.finalizedAtUTC != rhs.finalizedAtUTC {
                    return lhs.finalizedAtUTC
                        > rhs.finalizedAtUTC
                }
                return lhs.captureRevisionID.description
                    < rhs.captureRevisionID.description
            }
        return PersistedCaptureInventoryResult(
            captures: sorted,
            quarantinedArtifacts: quarantined.sorted {
                $0.url.path < $1.url.path
            },
            enumerationFailures: enumerationFailures
        )
    }

    /// Revalidates the canonical finalized directory and matching
    /// export archive for `captureRevisionID` and returns a fresh
    /// record. Returns nil when the finalized revision can no longer
    /// be proven (missing, invalid, or manifest identity mismatch). A
    /// stale or missing archive never blocks adoption; it simply
    /// leaves the record without an export slot.
    public func validatedRecord(
        captureRevisionID: CaptureRevisionID
    ) -> PersistedCaptureRecord? {
        let directory = finalizedDirectory(
            for: captureRevisionID
        )
        guard let report = try? BundleDirectoryValidator.validate(
            root: directory,
            limits: limits
        ), report.manifest.captureRevisionID == captureRevisionID
        else {
            return nil
        }

        var exportArchive: URL?
        var exportValidation: BundleValidationReport?
        let archive = exportArchiveURL(
            for: captureRevisionID
        )
        if FileManager.default.fileExists(atPath: archive.path),
           let archiveReport =
            try? StoredCaptureBundleArchiveValidator.validate(
                archive: archive,
                limits: limits
            ),
           archiveReport.manifest.captureRevisionID
                == captureRevisionID,
           archiveReport.bundleDigest == report.bundleDigest
        {
            exportArchive = archive
            exportValidation = archiveReport
        }

        return PersistedCaptureRecord(
            captureRevisionID: captureRevisionID,
            captureSeriesID: report.manifest.captureSeriesID,
            finalizedAtUTC: report.manifest.finalizedAtUTC,
            finalizedDirectory: directory,
            finalizedValidation: report,
            exportArchive: exportArchive,
            exportValidation: exportValidation
        )
    }

    /// Deletes the local copy of one revision: the canonical finalized
    /// directory and the canonical export archive. Candidate paths are
    /// always reconstructed inside the app-owned roots from the
    /// manifest-derived revision identity, never taken from stored
    /// path strings.
    ///
    /// The finalized directory is removed only after its manifest is
    /// reread and the declared `capture_revision_id` reconfirmed. A
    /// missing archive is fine. Partial failures never report success:
    /// everything left on disk is returned in `remaining` so it stays
    /// discoverable for retry.
    public func deleteCapture(
        captureRevisionID: CaptureRevisionID
    ) -> PersistedCaptureDeletionResult {
        let fileManager = FileManager.default
        var removed: [URL] = []
        var remaining:
            [PersistedCaptureRemainingArtifact] = []

        let directory = finalizedDirectory(
            for: captureRevisionID
        )
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ) {
            if !isDirectory.boolValue {
                remaining.append(
                    PersistedCaptureRemainingArtifact(
                        url: directory,
                        reason:
                            "the finalized slot is not a directory; revision identity cannot be reconfirmed"
                    )
                )
            } else if let refusal =
                identityReconfirmationFailure(
                    directory: directory,
                    captureRevisionID: captureRevisionID
                )
            {
                remaining.append(
                    PersistedCaptureRemainingArtifact(
                        url: directory,
                        reason: refusal
                    )
                )
            } else {
                do {
                    try fileManager.removeItem(at: directory)
                    removed.append(directory)
                } catch {
                    remaining.append(
                        PersistedCaptureRemainingArtifact(
                            url: directory,
                            reason:
                                "finalized directory removal failed: "
                                + Self.diagnostic(error)
                        )
                    )
                }
            }
        }

        // The archive path is the revision's own export slot inside the
        // app-owned exports root. It is derived wrapper data, not
        // capture authority, so whatever occupies the slot belongs to
        // this revision's deletion transaction.
        let archive = exportArchiveURL(
            for: captureRevisionID
        )
        if fileManager.fileExists(atPath: archive.path) {
            do {
                try fileManager.removeItem(at: archive)
                removed.append(archive)
            } catch {
                remaining.append(
                    PersistedCaptureRemainingArtifact(
                        url: archive,
                        reason:
                            "export archive removal failed: "
                            + Self.diagnostic(error)
                    )
                )
            }
        }

        return PersistedCaptureDeletionResult(
            captureRevisionID: captureRevisionID,
            removed: removed,
            remaining: remaining
        )
    }

    /// Removes a previously quarantined artifact. Removal is refused
    /// unless the artifact resolves to a direct child of one of the
    /// app-owned capture roots, so deletion can never escape the
    /// capture roots through a fabricated or redirected path.
    public func removeArtifact(
        _ artifact: PersistedCaptureQuarantinedArtifact
    ) throws {
        let resolved = artifact.url
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let parent = resolved.deletingLastPathComponent()
        let roots = [
            finalizedRoot
                .standardizedFileURL
                .resolvingSymlinksInPath(),
            exportsRoot
                .standardizedFileURL
                .resolvingSymlinksInPath(),
        ]
        guard roots.contains(parent) else {
            throw PersistedCaptureInventoryError
                .unsafeArtifactLocation
        }
        try FileManager.default.removeItem(at: artifact.url)
    }

    /// The canonical finalized directory URL for a validated revision
    /// identity. Used by the host for adoption and export; never
    /// derived from a stored path string.
    public func finalizedDirectory(
        for captureRevisionID: CaptureRevisionID
    ) -> URL {
        finalizedRoot.appendingPathComponent(
            captureRevisionID.description,
            isDirectory: true
        )
    }

    /// The canonical export archive URL for a validated revision
    /// identity.
    public func exportArchiveURL(
        for captureRevisionID: CaptureRevisionID
    ) -> URL {
        exportsRoot.appendingPathComponent(
            captureRevisionID.description + ".htdtcapture",
            isDirectory: false
        )
    }

    private enum ChildKind {
        case directory
        case regularFile
        case symbolicLink
        case unreadable
        case other
    }

    private func childKind(_ url: URL) -> ChildKind {
        guard let values = try? url.resourceValues(
            forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        ) else {
            return .unreadable
        }
        if values.isSymbolicLink == true {
            return .symbolicLink
        }
        if values.isDirectory == true {
            return .directory
        }
        if values.isRegularFile == true {
            return .regularFile
        }
        return .other
    }

    private func children(
        of root: URL,
        failures: inout [String]
    ) -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: root.path,
            isDirectory: &isDirectory
        ) else {
            // A missing root is an empty inventory, not a failure.
            return []
        }
        guard isDirectory.boolValue else {
            failures.append(
                root.lastPathComponent
                    + " exists but is not a directory"
            )
            return []
        }
        do {
            return try fileManager
                .contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                    ],
                    options: []
                )
                .sorted {
                    $0.lastPathComponent
                        < $1.lastPathComponent
                }
        } catch {
            failures.append(
                root.lastPathComponent
                    + " could not be enumerated: "
                    + Self.diagnostic(error)
            )
            return []
        }
    }

    /// Rereads the canonical manifest and proves the directory still
    /// declares the selected revision identity. A nil return means the
    /// directory is proven to belong to `captureRevisionID`.
    private func identityReconfirmationFailure(
        directory: URL,
        captureRevisionID: CaptureRevisionID
    ) -> String? {
        let manifestURL = directory.appendingPathComponent(
            "manifest.json",
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: manifestURL) else {
            return "manifest could not be read; revision identity"
                + " was not reconfirmed"
        }
        guard let manifest = try? JSONDecoder().decode(
            BundleManifest.self,
            from: data
        ) else {
            return "manifest could not be decoded; revision identity"
                + " was not reconfirmed"
        }
        guard let canonical = try? manifest.canonicalBytes(),
              canonical == data
        else {
            return "manifest is not canonical; revision identity"
                + " was not reconfirmed"
        }
        guard manifest.captureRevisionID == captureRevisionID
        else {
            return "manifest revision "
                + manifest.captureRevisionID.description
                + " does not match the selected revision "
                + captureRevisionID.description
        }
        return nil
    }

    private static func diagnostic(_ error: Error) -> String {
        let mirror = Mirror(reflecting: error)
        if mirror.displayStyle == .enum {
            var text = String(describing: error)
            if let paren = text.firstIndex(of: "(") {
                text = String(text[text.startIndex..<paren])
            }
            return String(describing: type(of: error))
                + "."
                + text
        }
        let nsError = error as NSError
        return String(describing: type(of: error))
            + ":"
            + nsError.domain
            + ":"
            + String(nsError.code)
    }
}
