# Localization glossary & conventions (legacy bolph71656-ai/HTDT-Capture#399)

HTDT Capture uses **one Apple-native localization authority**:
`App/ja.lproj/Localizable.strings`, where the **English source string
is the key**. All user-visible prose — SwiftUI labels, coordinator
status messages, scan-guidance copy, and VoiceOver summaries — resolves
through `String(localized:)` / `LocalizedStringKey` into that catalog.

Rules enforced by `tools/localization_audit.py` (run locally, phase-0):

- No hand-rolled bilingual helpers (`HostLocalization`-style pickers)
  and no `Locale.preferredLanguages` inference in production code.
- Interpolated strings use format templates:
  `String(format: String(localized: "... %@/%lld ..."), args)` — never
  `\(value)` concatenation.
- Domain code (Core/Platform) stays language-neutral: it emits typed
  identifiers/values, and the localized lookup happens where the string
  is produced for display.
- Untranslatable tokens (language names `English`/`日本語`, bare
  punctuation `)`) get identity entries (`"English" = "English"`).
- `%d`/`%lld`/`%@` placeholders must appear identically in key and
  Japanese value (positional `%1$@` allowed where order differs).

## Canonical terminology

| English | Japanese | Notes |
|---|---|---|
| capture | キャプチャ | |
| revision | リビジョン | |
| (capture) authority | 権威 | the spatial/annotation authority records |
| evidence | 証拠 | |
| mission | ミッション | |
| (task) plan | プラン | |
| equipment | 機器 | rack gear, devices |
| rack | ラック | |
| region | 領域 | scan-coverage region |
| room | 部屋 | "RoomPlan" stays untranslated |
| scan | スキャン | |
| measurement | 計測（値） | |
| annotation | 注釈 | |
| bundle | バンドル | `.htdtcapture` archive |
| catalog | カタログ | equipment catalog |
| coordinate space | 座標空間 | |
| observation | 観測 | |
| draft | 下書き | |
| commit / committed | 確定 / 確定済み | "commit" in the finalize sense |
| finalize / finalized | 確定 / 確定済み | same word as commit |
| reobserve / revisit | 再観測 | |
| serial number | シリアル番号 | |
| device | デバイス | iPhone/iPad hardware |
| item | 項目/機器 | prefer 機器 for equipment items |
| label | ラベル | UI label / equipment label |
| frame | フレーム | camera frame |
| timestamp | タイムスタンプ | |
| settings | 設定 | |
| task | タスク | |
| error | エラー | |
| required / optional | 必須 / 任意 | |
| ready | 準備完了 | state "Ready" = 準備完了 |
| unavailable | 利用できません/なし | context-dependent |
| marked intentional | 意図的として宣言 | coverage regions |
| lower/level/upper room | 下部/水平/上部 | pitch-band names |
| front…rear…left/right | 前方…後方…左/右 | direction octants |

## Writing new strings

1. Write the English string inline where it renders — the literal is
   the key.
2. Add `"English" = "Japanese";` to `App/ja.lproj/Localizable.strings`.
3. For dynamic content use `String(format:)` with a full-sentence
   template so Japanese word order is free; do not concatenate
   fragments that differ per language.
4. Run `python3 tools/localization_audit.py` before committing — it fails on missing
   keys, specifier mismatches, duplicate keys, and reintroduced
   `HostLocalization`/`preferredLanguages` code.
