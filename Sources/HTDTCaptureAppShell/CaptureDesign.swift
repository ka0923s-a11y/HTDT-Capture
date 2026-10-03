import Foundation
import SwiftUI
import HTDTCaptureCore
#if os(iOS)
import UIKit
#endif

/// Shared visual design tokens for HTDT Capture (legacy bolph71656-ai/HTDT-Capture#361/legacy bolph71656-ai/HTDT-Capture#364).
///
/// A small presentation layer over native SwiftUI components — not a
/// custom chrome framework. Every role maps to system typography,
/// system colors, and system materials so Dynamic Type, light/dark
/// appearance, and accessibility stay platform-managed.
public enum CaptureDesign {

    /// 8-point rhythm (legacy bolph71656-ai/HTDT-Capture#364 §2.5).
    public enum Spacing {
        /// icon↔text micro gap
        public static let micro: CGFloat = 4
        /// row / control spacing
        public static let row: CGFloat = 8
        /// compact group spacing
        public static let group: CGFloat = 12
        /// standard edge padding
        public static let edge: CGFloat = 16
        /// major section separation
        public static let section: CGFloat = 24
        /// hero / empty-state separation
        public static let hero: CGFloat = 32
    }

    /// Semantic typography roles (legacy bolph71656-ai/HTDT-Capture#361 §5, legacy bolph71656-ai/HTDT-Capture#364 §2.4). Use these
    /// instead of one-off `.font(...)` combinations.
    public enum Typography {
        /// Task-level headline under a navigation title.
        public static let taskHeadline = Font.headline.weight(.semibold)
        /// Section heading inside content.
        public static let sectionHeading = Font.subheadline.weight(.semibold)
        /// Primary body text.
        public static let body = Font.body
        /// Secondary / supporting metadata.
        public static let secondary = Font.callout
        /// Compact status label (CaptureStatusView).
        public static let status = Font.caption.weight(.semibold)
        /// Numeric metric readout.
        public static let metric = Font.caption.monospacedDigit()
        /// Technical provenance (UUIDs, digests, payload paths).
        public static let technical = Font.caption.monospaced()
        /// Fine technical print.
        public static let technicalSmall = Font.caption2.monospaced()
    }
}

public extension CaptureColorRole {
    /// The system color backing each semantic role (legacy bolph71656-ai/HTDT-Capture#364 §14).
    var color: Color {
        switch self {
        case .accent: return .accentColor
        case .success: return .green
        case .attention: return .orange
        case .blocked: return .red
        case .informational: return .blue
        case .unknown: return .secondary
        case .derived: return .purple
        case .secondary: return .secondary
        }
    }
}

public extension CaptureSemanticStatus {
    /// Localized label resolved through the app string tables.
    var localizedLabel: String {
        String(localized: String.LocalizationValue(labelKey))
    }
}

/// Compact status presentation (legacy bolph71656-ai/HTDT-Capture#361 §2): symbol + short text +
/// semantic color, so no state is ever conveyed by color alone.
public struct CaptureStatusView: View {
    public let status: CaptureSemanticStatus

    public init(_ status: CaptureSemanticStatus) {
        self.status = status
    }

    public var body: some View {
        Label(
            status.localizedLabel,
            systemImage: status.symbolName
        )
        .font(CaptureDesign.Typography.status)
        .foregroundStyle(status.colorRole.color)
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .combine)
    }
}

/// LabeledContent-style row that renders a semantic status as its
/// value — symbol + label, not color alone.
public struct CaptureStatusContent: View {
    public let label: LocalizedStringKey
    public let status: CaptureSemanticStatus

    public init(
        _ label: LocalizedStringKey,
        status: CaptureSemanticStatus
    ) {
        self.label = label
        self.status = status
    }

    public var body: some View {
        LabeledContent(label) {
            CaptureStatusView(status)
        }
    }
}

/// Inline advisory / warning / blocking notice surface (legacy bolph71656-ai/HTDT-Capture#361 §4,
/// legacy bolph71656-ai/HTDT-Capture#364 §12): tinted background, icon, title, message and an optional
/// recovery action. Used instead of raw colored paragraphs.
public struct CaptureNotice: View {
    public let status: CaptureSemanticStatus
    public let title: LocalizedStringKey
    public let message: LocalizedStringKey?
    public let actionTitle: LocalizedStringKey?
    public let action: (() -> Void)?

    public init(
        status: CaptureSemanticStatus,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.status = status
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(
            alignment: .top,
            spacing: CaptureDesign.Spacing.group
        ) {
            Image(systemName: status.symbolName)
                .font(.title3)
                .foregroundStyle(status.colorRole.color)
                .accessibilityHidden(true)
            VStack(
                alignment: .leading,
                spacing: CaptureDesign.Spacing.micro
            ) {
                Text(title)
                    .font(CaptureDesign.Typography.sectionHeading)
                if let message {
                    Text(message)
                        .font(CaptureDesign.Typography.secondary)
                        .foregroundStyle(.secondary)
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, CaptureDesign.Spacing.micro)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(CaptureDesign.Spacing.group)
        .background(
            status.colorRole.color.opacity(0.12),
            in: RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
    }
}

/// Designed first-use / empty / error state (legacy bolph71656-ai/HTDT-Capture#361 §7, legacy bolph71656-ai/HTDT-Capture#364 §3.1):
/// answers what happened, whether it is a problem, and what the
/// operator can do next.
public struct CaptureEmptyState: View {
    public let symbolName: String
    public let title: LocalizedStringKey
    public let message: LocalizedStringKey
    public let primaryActionTitle: LocalizedStringKey?
    public let primaryAction: (() -> Void)?
    public let secondaryActionTitle: LocalizedStringKey?
    public let secondaryAction: (() -> Void)?

    public init(
        symbolName: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        primaryActionTitle: LocalizedStringKey? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryActionTitle: LocalizedStringKey? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.symbolName = symbolName
        self.title = title
        self.message = message
        self.primaryActionTitle = primaryActionTitle
        self.primaryAction = primaryAction
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        VStack(spacing: CaptureDesign.Spacing.group) {
            Image(systemName: symbolName)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: CaptureDesign.Spacing.row) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(CaptureDesign.Typography.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let primaryActionTitle, let primaryAction {
                Button(action: primaryAction) {
                    Text(primaryActionTitle)
                        .font(CaptureDesign.Typography.taskHeadline)
                        .frame(maxWidth: 280)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if let secondaryActionTitle, let secondaryAction {
                Button(secondaryActionTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
            }
        }
        .padding(CaptureDesign.Spacing.hero)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// One consistent treatment for technical provenance (legacy bolph71656-ai/HTDT-Capture#361 §6):
/// UUIDs, hashes, payload paths, schema tokens — monospaced,
/// secondary, selectable, never at primary-task hierarchy.
public struct CaptureTechnicalDetail: View {
    public let label: LocalizedStringKey
    public let value: String

    public init(_ label: LocalizedStringKey, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(CaptureDesign.Typography.technical)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

/// Freestanding monospaced provenance line (digests, refs) for places
/// where a labeled row does not fit.
public struct CaptureTechnicalText: View {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var body: some View {
        Text(value)
            .font(CaptureDesign.Typography.technical)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}

/// Page/task header (legacy bolph71656-ai/HTDT-Capture#364 L0–L1): the current task statement with an
/// optional trailing semantic status.
public struct CaptureTaskHeader: View {
    private let titleText: Text
    public let subtitle: LocalizedStringKey?
    public let status: CaptureSemanticStatus?

    public init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        status: CaptureSemanticStatus? = nil
    ) {
        self.titleText = Text(title)
        self.subtitle = subtitle
        self.status = status
    }

    /// Verbatim title for operator-provided names — never re-parsed
    /// as a localization pattern.
    public init(
        verbatimTitle: String,
        subtitle: LocalizedStringKey? = nil,
        status: CaptureSemanticStatus? = nil
    ) {
        self.titleText = Text(verbatim: verbatimTitle)
        self.subtitle = subtitle
        self.status = status
    }

    public var body: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: CaptureDesign.Spacing.group
        ) {
            VStack(
                alignment: .leading,
                spacing: CaptureDesign.Spacing.micro
            ) {
                titleText
                    .font(CaptureDesign.Typography.taskHeadline)
                if let subtitle {
                    Text(subtitle)
                        .font(CaptureDesign.Typography.secondary)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let status {
                CaptureStatusView(status)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

public extension View {
    /// The standard prominent primary-task action treatment (legacy bolph71656-ai/HTDT-Capture#361 §3):
    /// one per screen/task — borderedProminent + large control size.
    @ViewBuilder
    func capturePrimaryAction() -> some View {
        buttonStyle(.borderedProminent)
            .controlSize(.large)
    }

    /// Secondary-task action treatment: standard bordered.
    @ViewBuilder
    func captureSecondaryAction() -> some View {
        buttonStyle(.bordered)
    }
}

/// Whether the current layout should present the adaptive two-pane
/// composition (legacy bolph71656-ai/HTDT-Capture#362) — delegates to the pure
/// `CaptureAdaptiveLayoutDecision` in Core so the rule stays
/// unit-testable and identical across platforms.
public typealias CaptureAdaptiveLayout = CaptureAdaptiveLayoutDecision

/// Adaptive two-pane container (legacy bolph71656-ai/HTDT-Capture#362): on regular width the leading
/// and trailing content render side-by-side in their own scrolling
/// columns; on compact width they compose back into one list. Content
/// stays the same in both modes — only the panes change — so workflow
/// and selection state survive size transitions.
public struct CaptureAdaptivePanes<
    Leading: View,
    Trailing: View
>: View {
    /// Width of the leading pane on regular-width layouts.
    public let leadingPaneWidth: CGFloat
    @ViewBuilder public let leading: () -> Leading
    @ViewBuilder public let trailing: () -> Trailing

    #if os(iOS)
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        leadingPaneWidth: CGFloat = 380,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.leadingPaneWidth = leadingPaneWidth
        self.leading = leading
        self.trailing = trailing
    }

    public var body: some View {
        GeometryReader { geometry in
            if usesPanes(availableWidth: geometry.size.width) {
                HStack(alignment: .top, spacing: 0) {
                    List { leading() }
                        .frame(
                            width: min(
                                leadingPaneWidth,
                                geometry.size.width * 0.45
                            )
                        )
                        .scrollContentBackground(.hidden)
                    Divider()
                    List { trailing() }
                }
            } else {
                List {
                    leading()
                    trailing()
                }
            }
        }
    }

    private func usesPanes(availableWidth: CGFloat) -> Bool {
        #if os(iOS)
        let regularWidthClass = horizontalSizeClass == .regular
        #else
        let regularWidthClass = false
        #endif
        return CaptureAdaptiveLayoutDecision.prefersPanes(
            isRegularWidthClass: regularWidthClass,
            availableWidth: availableWidth,
            isAccessibilityDynamicType:
                dynamicTypeSize.isAccessibilitySize
        )
    }
}

