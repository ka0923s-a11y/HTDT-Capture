import Foundation
import Testing
@testable import HTDTCaptureCore

private func makeSettingsDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    return root
}

// MARK: - Store contract (legacy bolph71656-ai/HTDT-Capture#338)

@Test
func settingsLoadReturnsDefaultsWhenFileMissing() throws {
    let root = try makeSettingsDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let settings = try CaptureAppSettingsStore(
        captureRoot: root
    ).load()
    #expect(settings == CaptureAppSettings())
    #expect(
        settings.storagePrivacy.finalizedBackupPolicy
            == .backupEligible
    )
    #expect(settings.presentation.guidanceCuesEnabled)
    #expect(settings.presentation.lengthDisplayUnit == .meter)
    #expect(
        settings.captureDefaults.defaultTaskProfileIdentifier == nil
    )
    #expect(!settings.captureDefaults.returnToStartCheckEnabled)
}

@Test
func settingsRoundTripPreservesEverySection() throws {
    let root = try makeSettingsDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    var settings = CaptureAppSettings()
    settings.presentation.guidanceCuesEnabled = false
    settings.presentation.lengthDisplayUnit = .millimeter
    settings.captureDefaults.defaultTaskProfileIdentifier =
        CaptureTaskProfile.roomAndListeningPosition.identifier
    settings.captureDefaults.returnToStartCheckEnabled = true
    settings.storagePrivacy.finalizedBackupPolicy =
        .excludedFromBackup

    let store = CaptureAppSettingsStore(captureRoot: root)
    try store.save(settings)
    #expect(try store.load() == settings)
}

@Test
func settingsSaveOverwritesAtomically() throws {
    let root = try makeSettingsDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = CaptureAppSettingsStore(captureRoot: root)
    try store.save(CaptureAppSettings())
    var updated = CaptureAppSettings()
    updated.presentation.lengthDisplayUnit = .foot
    try store.save(updated)
    #expect(try store.load() == updated)
}

@Test
func settingsCorruptFileFailsClosed() throws {
    let root = try makeSettingsDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = CaptureAppSettingsStore(captureRoot: root)
    try Data("not json".utf8).write(to: store.fileURL)
    #expect(throws: CaptureAppSettingsError.unreadableDocument) {
        try store.load()
    }
}

@Test
func settingsSchemaMismatchFailsClosed() throws {
    let root = try makeSettingsDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = CaptureAppSettingsStore(captureRoot: root)
    let document = """
        {
            "schema": "htdt.capture.app-settings",
            "schema_version": "9.9.9",
            "presentation": {}
        }
        """
    try Data(document.utf8).write(to: store.fileURL)
    #expect(throws: CaptureAppSettingsError.schemaMismatch) {
        try store.load()
    }
}

@Test
func settingsUnknownSchemaFailsClosed() throws {
    let root = try makeSettingsDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = CaptureAppSettingsStore(captureRoot: root)
    let document = """
        {
            "schema": "htdt.other.document",
            "schema_version": "1.0.0"
        }
        """
    try Data(document.utf8).write(to: store.fileURL)
    #expect(throws: CaptureAppSettingsError.schemaMismatch) {
        try store.load()
    }
}

@Test
func settingsMissingSectionsDecodeToDefaults() throws {
    // A document written by an older build without the newer
    // sections must keep working — sections decode independently.
    let json = """
        {
            "schema": "htdt.capture.app-settings",
            "schema_version": "1.0.0",
            "storage_privacy": {
                "finalized_backup_policy": "excluded_from_backup"
            }
        }
        """
    let settings = try JSONDecoder().decode(
        CaptureAppSettings.self,
        from: Data(json.utf8)
    )
    #expect(
        settings.storagePrivacy.finalizedBackupPolicy
            == .excludedFromBackup
    )
    #expect(settings.presentation == CapturePresentationPreferences())
    #expect(settings.captureDefaults == CaptureWorkflowDefaults())
}

@Test
func settingsMissingKeysInsideSectionDecodeToDefaults() throws {
    let json = """
        {
            "schema": "htdt.capture.app-settings",
            "schema_version": "1.0.0",
            "presentation": {
                "guidance_cues_enabled": false
            }
        }
        """
    let settings = try JSONDecoder().decode(
        CaptureAppSettings.self,
        from: Data(json.utf8)
    )
    #expect(!settings.presentation.guidanceCuesEnabled)
    #expect(settings.presentation.lengthDisplayUnit == .meter)
}

// MARK: - Workflow defaults (legacy bolph71656-ai/HTDT-Capture#338)

@Test
func defaultTaskProfileResolvesKnownIdentifier() {
    var defaults = CaptureWorkflowDefaults()
    #expect(defaults.defaultTaskProfile == nil)

    defaults.defaultTaskProfileIdentifier =
        CaptureTaskProfile.geometryOnly.identifier
    #expect(
        defaults.defaultTaskProfile
            == CaptureTaskProfile.geometryOnly
    )
}

@Test
func defaultTaskProfileDegradesUnknownIdentifierToNil() {
    var defaults = CaptureWorkflowDefaults()
    defaults.defaultTaskProfileIdentifier = "unknown-future-profile"
    #expect(defaults.defaultTaskProfile == nil)
}

@Test
func standalonePresetsCoverGeometryAndListeningPosition() {
    #expect(
        CaptureTaskProfile.standalonePreset(
            identifier: CaptureTaskProfile.geometryOnly.identifier
        ) == .geometryOnly
    )
    #expect(
        CaptureTaskProfile.standalonePreset(
            identifier: CaptureTaskProfile.roomAndListeningPosition
                .identifier
        ) == .roomAndListeningPosition
    )
    #expect(
        CaptureTaskProfile.standalonePreset(
            identifier: "theater-layout-custom"
        ) == nil
    )
}

// MARK: - Display units (legacy bolph71656-ai/HTDT-Capture#338 section A)

@Test
func lengthDisplayUnitFormatsCanonicalMeters() {
    #expect(LengthDisplayUnit.meter.format(lengthMeters: 1.5) == "1.5 m")
    #expect(
        LengthDisplayUnit.millimeter.format(lengthMeters: 1.5)
            == "1,500 mm"
    )
}

@Test
func lengthDisplayUnitConvertsToInchesAndFeet() {
    #expect(LengthDisplayUnit.inch.format(lengthMeters: 0.254) == "10 in")
    #expect(
        LengthDisplayUnit.foot.format(lengthMeters: 0.3048)
            == "1 ft"
    )
}
