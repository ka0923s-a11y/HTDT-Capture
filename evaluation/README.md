# Evaluation scaffold (issue bolph71656-ai/HTDT-Capture#274)

Common result/provenance scaffold for the iOS 27 capability program
(legacy bolph71656-ai/HTDT-Capture#266). One **evaluation record** (`schemas/evaluation-record-v1.schema.json`)
documents one lane run: campaign/protocol identity, environment
(app commit, iOS/Xcode/SDK, device), configuration, fixture case ID,
metrics, result, and an adoption decision.

Validate records locally:

```sh
python3 tools/evaluation/validate_record.py evaluation/records/<file>.json
```

## Principles

1. **Numerical facts use numerical measurement.** Pose error, mask IoU,
   latency, depth availability, thermal state — never LLM-judged.
2. **Generated behavior uses repeated/rate-based evaluation.** One
   successful Foundation Models response certifies nothing; report
   trial counts and distributions.
3. **Compare against the simplest existing baseline** — deterministic,
   manual, or native behavior the feature must beat or complement.
4. **Authority violations are hard failures.** No aggregate score excuses
   fabricated geometry, overwritten raw observations, or unsafe
   generated actions (`authority_violation` failure category).
5. **Complexity/resource cost counts against benefit** — model assets,
   context, tools, and operator steps must earn their cost.

## Lanes

Each lane file under `evaluation/lanes/` defines its fixtures, metric
dictionary, and decision scope. Add a lane's details only when the
feature behind it needs an adoption decision.

| Lane | Feature issue | File |
|------|---------------|------|
| baseline-0 | current authoritative capture baseline | `lanes/baseline-0.md` |
| lane-a | legacy bolph71656-ai/HTDT-Capture#277 source-quality preflight | `lanes/lane-a-source-preflight.md` |
| lane-b | legacy bolph71656-ai/HTDT-Capture#275 high-quality visual evidence | `lanes/lane-b-visual-evidence.md` |
| lane-c | legacy bolph71656-ai/HTDT-Capture#268 reference objects | `lanes/lane-c-reference-objects.md` |
| lane-d | legacy bolph71656-ai/HTDT-Capture#269 segmentation + depth fusion | `lanes/lane-d-segmentation-fusion.md` |
| lane-e | legacy bolph71656-ai/HTDT-Capture#270 equipment identity | `lanes/lane-e-equipment-identity.md` |
| lane-f | legacy bolph71656-ai/HTDT-Capture#271 Core AI prototype | `lanes/lane-f-core-ai.md` |
| lane-g | legacy bolph71656-ai/HTDT-Capture#272 scan copilot | `lanes/lane-g-scan-copilot.md` |

## Regression triggers

Rerun **only the affected lane** after: OS/Xcode/SDK/framework updates;
model variant changes; prompt/schema/tool changes; Vision
preprocessing/fusion/orientation-transform changes; visual
profile/video/HDR/photo-setting changes; reference-object retraining;
Core AI model changes; legacy bolph71656-ai/HTDT-Capture#273 admission-policy changes that alter
input timing/quality.

## Fixture/privacy policy

No private household imagery in this public repository. Prefer staged
fixtures, redistributable licensed data, synthetic data with provenance,
or cropped/redacted samples. For private local fixtures, commit only the
non-sensitive case manifest/count, protocol, commands, aggregate
results, and decision — mark `private_fixture: true` in the record.

## Foundation Models provenance

Record only what Apple exposes plus app-controlled revisions: OS build,
`SystemLanguageModel.variant` when exposed, availability/locale,
context size, prompt/session/schema/toolset revision, catalog/index
revision, and measured token use where meaningful. Never invent a
model-weight build ID.
