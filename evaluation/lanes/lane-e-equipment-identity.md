# lane-e — equipment identity (#270)

Protocol revision: **v1** (initial scaffold)

Compare: (1) direct Vision OCR/barcode + deterministic matcher; (2) + Foundation Models multimodal interpretation; (3) optional OCR/barcode tool route where justified; (4) deterministic catalog lookup vs focused Spotlight; (5) ordinary vs lane-b visual source.

Metrics: exact manufacturer/model accuracy; catalog recall@1/@3; raw model/serial preservation; false-confident suggestion rate; abstention behavior; operator correction rate/time; context/token usage and overflow; unnecessary tool calls; latency/resource cost.

## Implementation state (PR #287)

Built (off by default behind `equipment_identity_ai_assist_enabled`, iOS 26+ / `canImport(FoundationModels)`):

- `EquipmentIdentityAIAdvisor` — one fresh task-scoped `LanguageModelSession` per request; `SystemLanguageModel.availability` + `supportedLanguages` checks; 4096-token budget via `EquipmentIdentityAIBudget` (default → reduced retry) + `estimatedTokens` preflight; `@Generable` structured output; typed failure statuses (`.unavailable` / `.localeUnsupported` / `.contextOverflow` / `.validatorRejected` / `.generationFailed` / `.abstained`).
- `EquipmentIdentityAIValidator` — deterministic grounding gate: catalog keys ⊆ injected bounded slice; `evidenceLinks` ⊆ raw observations; manufacturer/model/serial must trace to raw OCR/barcode/candidate/catalog strings; `needsOperatorConfirmation` forced true.
- Advisory renders display-only in `EquipmentLabelScanSheet` ("AI suggestion (experimental)"); never enters `candidates`; deterministic result byte-identical when the lane is off or unavailable.

Deferred (SDK-gated, candidate future arms): Vision `OCRTool`/`BarcodeReaderTool` route (symbols absent from iOS 26.5 SDK; iOS-27-only in RC SDK — catalog facts currently injected as bounded prompt slice instead); `SystemLanguageModel.variant` provenance and image prompt segments (iOS 27 only); `GenerationOptions.ToolCallingMode` policy (iOS 27 only); focused Spotlight; long-lived session comparison arm (explicitly out of scope per #270).

## Pending runs (device-gated)

Foundation Models is unavailable in Simulator — never fake it; all FM-bearing runs below need iPhone 17 Pro / iOS 27.

- **sim-zero-impact** (Simulator, runnable now): flag OFF vs ON — deterministic scan result byte-identical; advisory reports `.unavailable`, no crash/hang, nothing auto-applied.
- **device-staged-labels** (device-gated): staged label set (per fixture/privacy policy) × {deterministic, deterministic+fm} — all metrics above plus per-run `tokenCount(for: transcript)`/`contextSize` telemetry (iOS 27+), latency/memory, thermal timeline.
- **Enablement gate**: no default enablement without measured benefit — adoption decision via evaluation record only after device-staged-labels completes (accuracy/recall up AND false-confident rate + operator-correction cost justified vs added context/tool cost).
