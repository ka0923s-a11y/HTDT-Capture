import Foundation

#if canImport(FoundationModels) && compiler(>=6.4)
import FoundationModels
#endif

/// The Foundation Models adapter for the scan copilot (#272).
///
/// Everything here is doubly gated:
///   1. `#if canImport(FoundationModels) && compiler(>=6.4)` —
///      the iOS-27-only API surface (`LanguageModelError`,
///      `SystemLanguageModel.variant`, `GenerationOptions
///      .toolCallingMode`, `Response.usage`) does not exist in older
///      SDKs, so builds on the iOS 26.5 toolchain compile the model
///      path out entirely and the copilot stays deterministic-only.
///   2. `#available(iOS 27.0, macOS 27.0, *)` + `SystemLanguageModel
///      .availability` + `supportsLocale` at runtime — on Simulator,
///      on pre-iOS-27 OS builds, on ineligible hardware, and for
///      unsupported locales the producer is never created and every
///      resolution falls back to `ScanCopilotBaseline`.
///
/// Per #272: one fresh `LanguageModelSession` per suggestion request
/// (no long-lived agent), no tools (`toolCallingMode = .disallowed`),
/// `contextSizeExceeded` is a normal failure — the input is rebuilt
/// smaller once via `context.reduced()`, never by silently dropping
/// diagnostics, and a second overflow yields the deterministic
/// advisory. Provenance records only fields the API actually
/// exposes: variant display name, OS version, locale, context size,
/// usage token counts, and the app-owned prompt revision.

/// Prompt/copy revision stamped into provenance — bump when the
/// instruction or prompt text changes so eval records stay
/// comparable (#272 audit field).
public let scanCopilotPromptRevision = "scan-copilot-v1"

/// Assembles the copilot's model producer for the current runtime.
public enum ScanCopilotModelProvider {
    /// A model producer, or nil when the model path is inert
    /// (Simulator, pre-iOS-27, older SDK toolchain, unavailable
    /// model, unsupported locale). Callers never need to know why —
    /// nil simply means deterministic-only.
    public static func makeProducer(
        locale: Locale = .current
    ) -> (any ScanCopilotModelProducing)? {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            let producer = FoundationScanCopilotModel(locale: locale)
            return producer.isUsable ? producer : nil
        }
        return nil
        #else
        return nil
        #endif
    }

    /// Coarse availability answer for the UI: `true` only when the
    /// model path can actually run on this runtime. The copilot UI
    /// never hides the deterministic chip; this only feeds the
    /// source caption.
    public static var modelPathAvailable: Bool {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            return FoundationScanCopilotModel().isUsable
        }
        return false
        #else
        return false
        #endif
    }
}

#if canImport(FoundationModels) && compiler(>=6.4)

/// What the model is allowed to return: enum-typed choices plus
/// whitelisted template/reason/ID tokens only — no free-form
/// instruction text, so unsafe-movement or finish semantics cannot
/// be expressed, let alone validated in.
@available(iOS 26.0, macOS 26.0, *)
@Generable(description:
    "One advisory next-step pick for a 3D room-scan operator."
)
public struct ScanCopilotDraftOutput: Sendable {
    @Guide(description:
        "One of the allowed_actions values from the prompt."
    )
    public var action: String

    @Guide(description:
        "One of the allowed_templates values matching the action."
    )
    public var template: String

    @Guide(description: "One of: low, normal, high.")
    public var priority: String

    @Guide(description:
        "An identifier from candidate_ids, or omit when the action " +
        "does not target a specific region or item."
    )
    public var targetID: String?

    @Guide(description:
        "Up to 6 values from allowed_reasons supporting the pick."
    )
    public var reasonCodes: [String]

    @Guide(description:
        "Identifiers of diagnostics rows that motivated the pick."
    )
    public var sourceDiagnosticIDs: [String]
}

/// iOS-27 Foundation Models producer. Each `suggest` builds a fresh
/// task-scoped session; nothing conversational survives a request.
@available(iOS 27.0, macOS 27.0, *)
public struct FoundationScanCopilotModel: ScanCopilotModelProducing {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Runtime availability: eligible hardware + enabled model +
    /// ready weights + supported locale.
    public var isUsable: Bool {
        let model = SystemLanguageModel.default
        guard model.availability == .available,
              model.supportsLocale(locale)
        else {
            return false
        }
        return true
    }

    static let instructionsText =
        """
        You pick one advisory next step for an operator scanning a \
        room. Choose an action from allowed_actions, a template from \
        allowed_templates, and reasons from allowed_reasons only. \
        Never invent actions, templates, identifiers, or reasons. \
        Never instruct the operator to finish or end the capture. \
        Never instruct physical movement unless \
        movement=unrestricted. When nothing is actionable, pick \
        no_action.
        """

    public func suggest(
        context: ScanCopilotContext
    ) async -> ScanCopilotModelOutcome {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            return ScanCopilotModelOutcome(
                draft: nil,
                failure: .modelUnavailable,
                provenance: nil
            )
        }
        guard model.supportsLocale(locale) else {
            return ScanCopilotModelOutcome(
                draft: nil,
                failure: .localeUnsupported,
                provenance: nil
            )
        }
        do {
            return try await request(
                context: context,
                model: model
            )
        } catch LanguageModelError.contextSizeExceeded(_) {
            // One bounded retry on the reduced context — diagnostics
            // shrink to the top rows, never silently to zero.
            do {
                return try await request(
                    context: context.reduced(),
                    model: model
                )
            } catch {
                return ScanCopilotModelOutcome(
                    draft: nil,
                    failure: .contextExceeded,
                    provenance: provenance(model: model, usage: nil)
                )
            }
        } catch {
            return ScanCopilotModelOutcome(
                draft: nil,
                failure: .generationFailed,
                provenance: provenance(model: model, usage: nil)
            )
        }
    }

    private func request(
        context: ScanCopilotContext,
        model: SystemLanguageModel
    ) async throws -> ScanCopilotModelOutcome {
        // Fresh task-scoped session per request — no tools, no
        // carried state.
        let session = LanguageModelSession(
            model: model,
            tools: [],
            instructions: Self.instructionsText
        )
        let options = GenerationOptions(
            temperature: 0.1,
            maximumResponseTokens: 256,
            toolCallingMode: .disallowed
        )
        let response = try await session.respond(
            to: context.promptDescription,
            generating: ScanCopilotDraftOutput.self,
            options: options
        )
        let output = response.content
        let draft = ScanCopilotModelDraft(
            actionID: output.action,
            templateID: output.template,
            priorityID: output.priority,
            targetID: output.targetID,
            reasonCodes: output.reasonCodes,
            sourceDiagnosticIDs: output.sourceDiagnosticIDs,
            contextDigest: context.contextDigest
        )
        return ScanCopilotModelOutcome(
            draft: draft,
            failure: nil,
            provenance: provenance(model: model, usage: response.usage)
        )
    }

    /// Provenance assembled strictly from API-exposed fields —
    /// variant display name, OS version, locale, context size, usage
    /// counts, and the app-owned prompt revision (#272).
    private func provenance(
        model: SystemLanguageModel,
        usage: LanguageModelSession.Usage?
    ) -> ScanCopilotModelProvenance {
        ScanCopilotModelProvenance(
            modelVariantDisplayName: model.variant.displayName,
            osVersion: ProcessInfo.processInfo
                .operatingSystemVersionString,
            localeIdentifier: locale.identifier,
            contextSizeLimit: model.contextSize,
            inputTokenCount: usage?.input.totalTokenCount,
            outputTokenCount: usage?.output.totalTokenCount,
            promptRevision: scanCopilotPromptRevision
        )
    }
}

#endif
