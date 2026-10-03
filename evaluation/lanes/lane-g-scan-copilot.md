# lane-g — scan copilot (legacy bolph71656-ai/HTDT-Capture#272)

Protocol revision: **v2** (implementation landed; device arm pending)

Compare: (1) existing deterministic guidance; (2) improved deterministic priority/rules + localized copy (`ScanCopilotBaseline` + `ScanCopilotCopy`); (3) fresh task-scoped Foundation Models suggestion (`FoundationScanCopilotModel`) after deterministic validation.

## Implemented pipeline (this PR)

Deterministic diagnostics (`CaptureQualityReport.diagnostics`, live coverage/guidance trackers) → `ScanCopilotContext` (bounded, schema `htdt.capture.scan_copilot_context` v1.0.0, Codable/Sendable, stable SHA-256 digest for equivalent-state debounce) → optional `ScanCopilotModelProducing` draft → `ScanCopilotValidator` → `ScanCopilotResolution` surfaced as an advisory chip ("What next?" in the expanded HUD).

Hard invariants in the implementation:

- Model output is `@Generable` constrained: enum-typed action/template/reason tokens only — no free-text instruction field exists. Unsafe-movement or finish semantics cannot be expressed by construction; `ScanCopilotValidator` independently re-checks (movement requires `ScanMovementCapability.unrestricted`, `review` requires the normal End/review affordance, unknown actions/templates/IDs/reasons/digest are rejected, `no_action` is rejected over error-severity diagnostics).
- The deterministic arm (`ScanCopilotBaseline`) always resolves a suggestion and is the fallback whenever the model path is unavailable, errors, or is rejected — the deterministic UX is complete on its own.
- Fresh task-scoped `LanguageModelSession` per request, `toolCallingMode = .disallowed`; `LanguageModelError.contextSizeExceeded` → one retry on `context.reduced()` → `.contextExceeded` fallback. Diagnostics shrink to top rows, never silently to zero.
- Double gating: `#if canImport(FoundationModels) && compiler(>=6.4)` at compile time (the iOS-27 SDK only) + `#available(iOS 27.0, macOS 27.0, *)` + `SystemLanguageModel.availability == .available` + `supportsLocale` at runtime. Pre-iOS-27 builds produce `makeProducer() == nil` — cleanly deterministic-only. Note (sim-verified): on the iOS 27 simulator `SystemLanguageModel.availability` still reports `.available`, so `makeProducer()` returns a live producer — generation then fails and the designed `modelUnavailableFallback` arm runs; the end result is the same deterministic suggestion with honest provenance.
- Provenance (`ScanCopilotModelProvenance`) records only API-exposed fields: `variant.displayName`, OS version, locale, `contextSize`, `Usage` token counts, app prompt revision — nothing fabricated.
- Suggestions are transient (in-memory resolution only); nothing persists to the working set.

## Arms for the device evaluation

| arm | code path | provenance marker |
|-----|-----------|-------------------|
| A: deterministic-only | `ScanCopilotEngine(model: nil)` / `makeProducer()` returns nil | `deterministicBaseline` |
| B: model-validated | `makeProducer()` returns `FoundationScanCopilotModel` and the draft validates | `modelValidated` |
| C: model-rejected | same as B but the validator rejects | `modelRejectedFallback` + violation list |

All three resolve the same `ScanCopilotSuggestion` type, so agreement/rejection metrics compare `suggestion.action`/`template`/`priority` per `contextDigest` directly.

Metrics (from v1): expected allowed-action agreement; structured-output validity; hallucinated IDs; deterministic validator rejection rate; accepted unsafe movement actions (must be zero); accepted inappropriate completion actions (must be zero); repetition/noise; operator task time/movement; context/token overflow; locale/model-unavailable fallback; latency/resource cost.

## Device-gated status (honest)

- Arms B/C are **unexercised in this repo's CI/dev environments**: Foundation Models is unavailable on Simulator, the iOS-27 device matrix requires iPhone 17 Pro + iOS 27 (legacy bolph71656-ai/HTDT-Capture#266), and `LanguageModelSession` on device is the only path that produces a real draft. On this Mac's toolchains: SwiftPM builds skip the FM adapter entirely (compiler <6.4); the Xcode-27 RC toolchain compiles it against the iOS 27 SDK.
- Unit-test coverage substitutes a `ScriptedCopilot` fake for the model: validator rejections (movement constrained ×2, finish-not-permitted, unknown action/template/ID/reason/digest, blocking no_action), acceptance of a conforming draft, engine fallback on `modelUnavailable`/rejection, baseline-never-suggests-movement under constraints, and baseline-passes-own-validator across 10 states. The *real* `@Generable` schema negotiation and the 4096-token `contextSizeExceeded` retry are device-only.
- No evaluation records are fabricated: a run requires a real `LanguageModelSession` environment block (`tools/evaluation/validate_record.py` requires real device fields), so record the model variant/OS/usage provenance from `ScanCopilotResolution.provenance` on-device, plus per-`contextDigest` arm outputs.
- Suggested on-device matrix: ≥3 scan phases (early/weak coverage, mid-scan tracking-limited, review-ready) × arms A/B × locales en/JA; count C-type rejections by `ScanCopilotValidationViolation` kind; assert zero accepted `move_to_gap`/`rescan_target` under non-`unrestricted` capability and zero accepted `review` outside permitted stages.

If deterministic guidance performs equivalently, do not ship the LLM path.
