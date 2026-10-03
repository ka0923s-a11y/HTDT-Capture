import Foundation
import SwiftUI
import HTDTCaptureCore

/// The single settings entry point (issue bolph71656-ai/HTDT-Capture#338). Groups device-local
/// controls into the taxonomy that keeps them out of capture
/// authority:
///
/// - A. Presentation preferences — UI-only; never change canonical
///   capture bytes or meaning.
/// - B. Device-local workflow defaults — seed a new capture; an
///   explicit per-capture or project/task choice always overrides.
/// - C. Storage & privacy — where finalized data lives and whether
///   the platform backup may include it (legacy bolph71656-ai/HTDT-Capture#305).
/// - D. Managed reference contexts — equipment catalogs and similar
///   imported context, surfaced with identity so a capture can show
///   exactly which context it used.
///
/// Settings persist as versioned app-local JSON; changing them never
/// rewrites or reinterprets an existing capture.
public struct CaptureSettingsView: View {
    public let settings: CaptureAppSettings
    /// The host-managed equipment catalog reference context (legacy bolph71656-ai/HTDT-Capture#211).
    public let equipmentCatalog: HTDTEquipmentCatalogSnapshot?
    /// Total bytes retained by finalized captures + export archives,
    /// for the storage summary row.
    public let retainedByteCount: Int64
    /// Persists a new settings document through the host.
    public let onChange: (CaptureAppSettings) -> Void
    /// Clears the durable equipment-catalog cache (legacy bolph71656-ai/HTDT-Capture#338); committed
    /// captures keep the exact equipment tuples they recorded.
    public let onClearEquipmentCatalog: () -> Void

    public init(
        settings: CaptureAppSettings = CaptureAppSettings(),
        equipmentCatalog: HTDTEquipmentCatalogSnapshot? = nil,
        retainedByteCount: Int64 = 0,
        onChange: @escaping (CaptureAppSettings) -> Void = { _ in },
        onClearEquipmentCatalog: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.equipmentCatalog = equipmentCatalog
        self.retainedByteCount = retainedByteCount
        self.onChange = onChange
        self.onClearEquipmentCatalog = onClearEquipmentCatalog
    }

    public var body: some View {
        List {
            presentationSection
            captureDefaultsSection
            dataAndBackupSection
            referenceContextsSection
        }
        .navigationTitle(
            String(localized: "Settings")
        )
    }

    private var presentationSection: some View {
        Section {
            Toggle(
                String(localized: "Haptic and spoken guidance cues"),
                isOn: binding(
                    \.presentation.guidanceCuesEnabled
                )
            )
            Picker(
                String(localized: "Length display unit"),
                selection: binding(
                    \.presentation.lengthDisplayUnit
                )
            ) {
                DescribedPickerOption(
                    title: String(localized: "Meters"),
                    detail: String(localized:
                        "Distances shown in meters (m).")
                ).tag(LengthDisplayUnit.meter)
                DescribedPickerOption(
                    title: String(localized: "Millimeters"),
                    detail: String(localized:
                        "Distances shown in millimeters (mm).")
                ).tag(LengthDisplayUnit.millimeter)
                DescribedPickerOption(
                    title: String(localized: "Inches"),
                    detail: String(localized:
                        "Distances shown in inches (in).")
                ).tag(LengthDisplayUnit.inch)
                DescribedPickerOption(
                    title: String(localized: "Feet"),
                    detail: String(localized:
                        "Distances shown in feet (ft).")
                ).tag(LengthDisplayUnit.foot)
            }
            Button(
                String(localized: "Reset presentation preferences")
            ) {
                var copy = settings
                copy.presentation = CapturePresentationPreferences()
                onChange(copy)
            }
        } header: {
            Text(String(localized: "Presentation"))
        } footer: {
            Text(
                String(
                    localized:
                        "Presentation choices only change how information is displayed or announced. They never change recorded capture data."
                )
            )
        }
    }

    private var captureDefaultsSection: some View {
        Section {
            Picker(
                String(localized: "Default capture task"),
                selection: Binding(
                    get: {
                        settings.captureDefaults
                            .defaultTaskProfileIdentifier
                    },
                    set: { identifier in
                        var copy = settings
                        copy.captureDefaults
                            .defaultTaskProfileIdentifier = identifier
                        onChange(copy)
                    }
                )
            ) {
                DescribedPickerOption(
                    title: String(localized:
                        "Choose for each capture"),
                    detail: String(localized:
                        "Ask which task profile to use every time a new capture starts.")
                ).tag(nil as String?)
                ForEach(
                    CaptureTaskProfile.standalonePresets,
                    id: \.identifier
                ) { profile in
                    DescribedPickerOption(
                        title: CaptureMissionNeeds.taskProfileName(
                            profile
                        ),
                        detail: CaptureMissionNeeds
                            .taskProfileDescription(
                                identifier: profile.identifier
                            )
                    )
                    .tag(profile.identifier as String?)
                }
            }
            Toggle(
                String(
                    localized:
                        "Return-to-start consistency check"
                ),
                isOn: binding(
                    \.captureDefaults.returnToStartCheckEnabled
                )
            )
        } header: {
            Text(String(localized: "Capture defaults"))
        } footer: {
            Text(
                String(
                    localized:
                        "A default applies when a new capture begins and stays changeable per capture. An explicit selection in the capture — or a project/task requirement — always wins, and the value the capture actually used is recorded with it."
                )
            )
        }
    }

    private var dataAndBackupSection: some View {
        Section {
            Picker(
                String(localized: "Finalized data backup"),
                selection: binding(
                    \.storagePrivacy.finalizedBackupPolicy
                )
            ) {
                DescribedPickerOption(
                    title: String(localized:
                        "May join device backup"),
                    detail: String(localized:
                        "Finalized captures may be included in the device backup, depending on system settings.")
                ).tag(FinalizedBackupPolicy.backupEligible)
                DescribedPickerOption(
                    title: String(localized: "Excluded from backup"),
                    detail: String(localized:
                        "Finalized captures are kept out of the device backup.")
                ).tag(FinalizedBackupPolicy.excludedFromBackup)
            }
            LabeledContent(
                String(localized: "Retained data"),
                value: ByteCountFormatter.string(
                    fromByteCount: retainedByteCount,
                    countStyle: .file
                )
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    String(
                        localized:
                            "Working scan data is kept app-private and is always excluded from device backup."
                    )
                )
                Text(
                    backupPolicyExplanation
                )
                Text(
                    String(
                        localized:
                            "Sharing or sending to HTDT is always an explicit action you choose — it is never tied to device backup."
                    )
                )
                Text(
                    String(
                        localized:
                            "Deleting a capture permanently removes its finalized copy and stored export archive from this device."
                    )
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "Data & backup"))
        } footer: {
            Text(
                String(
                    localized:
                        "The backup choice applies to finalized captures already on this device and to new ones."
                )
            )
        }
    }

    private var referenceContextsSection: some View {
        Section {
            if let equipmentCatalog {
                LabeledContent(
                    String(localized: "Equipment catalog"),
                    value: String(
                        format: String(localized: "%lld definitions"),
                        Int64(equipmentCatalog.definitions.count)
                    )
                )
                LabeledContent(
                    String(localized: "Authority version"),
                    value: equipmentCatalog.authorityVersion
                )
                .font(.caption.monospaced())
                Button(
                    String(
                        localized: "Clear equipment catalog cache"
                    ),
                    role: .destructive,
                    action: onClearEquipmentCatalog
                )
            } else {
                Text(
                    String(
                        localized:
                            "No equipment catalog imported. Import one from the annotation workspace to bind exact equipment definitions."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "Reference contexts"))
        } footer: {
            Text(
                String(
                    localized:
                        "An imported catalog is reference context only — a capture records the exact equipment identifiers it used, so clearing the cache never changes saved captures."
                )
            )
        }
    }

    private var backupPolicyExplanation: String {
        switch settings.storagePrivacy.finalizedBackupPolicy {
        case .backupEligible:
            return String(
                localized:
                    "Finalized captures and their export archives stay in this app's storage on this device and may be included in your device backup, depending on your system settings."
            )
        case .excludedFromBackup:
            return String(
                localized:
                    "Finalized captures and their export archives stay in this app's storage on this device and are excluded from device backup."
            )
        }
    }

    private func binding<T: Equatable>(
        _ keyPath: WritableKeyPath<CaptureAppSettings, T>
    ) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                var copy = settings
                copy[keyPath: keyPath] = newValue
                onChange(copy)
            }
        )
    }
}
