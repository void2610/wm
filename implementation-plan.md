# macOS ウィンドウマネージャー 実装プラン

AeroSpace ライクな機能 + Loop ライクなアニメーション品質を目指す、個人開発向けの実装計画。

---

## 1. プロジェクト概要

### ゴール

- 基本的なウィンドウ操作（フォーカス移動、フルスクリーン切替、半分・1/4 分割）をキーボードで一発
- 任意アプリの起動ショートカット
- TOML 設定ファイルを dotfiles で git 管理
- スナップ動作に綺麗なアニメーション付き UI を付与

### 非ゴール（割り切る）

- **tiling ではない**。Rectangle + ホットキーランチャー的な立ち位置に絞る
- **SIP 無効化を要求しない**。yabai 的な private API は使わない
- **マルチデスクトップ管理はしない**。最初は単一スペース前提で組む
- **Stage Manager との完全互換は追わない**

---

## 2. 技術スタック

| 領域 | 採用 | 補足 |
|---|---|---|
| 言語 | Swift 5.9+ | macOS 13+ ターゲット |
| UI | SwiftUI (MenuBarExtra) | 設定画面・プレビュー・ラジアルメニュー全て |
| ウィンドウ操作 | Accessibility API (`AXUIElement`) | `AXEnhancedUserInterface` も活用 |
| グローバルホットキー | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Sindre Sorhus 製。記録 UI 込み |
| アプリ起動 | `NSWorkspace.shared.openApplication` | bundle id 指定 |
| 設定パース | [TOMLKit](https://github.com/LebJe/TOMLKit) | AeroSpace と揃える |
| 設定監視 | `DispatchSource.makeFileSystemObjectSource` | ホットリロード |
| 自動更新 | [Sparkle](https://sparkle-project.org/) | Phase 5 で導入 |
| ロギング | `OSLog` | `Console.app` で追える |
| CLI 連携 (任意) | [swift-argument-parser](https://github.com/apple/swift-argument-parser) | `wm focus left` |

### Loop からの設計インスピレーション

- アニメーションのトーン統一 → 自前で `AnimationConstants.swift` を作って spring パラメータを一箇所に集約
- プレビューウィンドウ（スナップ先を予告する半透明 NSWindow）で「ぬるさ」を演出
- 実ウィンドウのリサイズには `AXEnhancedUserInterface = true` を一時的にセット

---

## 3. アーキテクチャ

```
┌──────────────────────────────────────────────┐
│  App (LSUIElement, MenuBarExtra)             │
├──────────────────────────────────────────────┤
│  HotkeyManager   │  ConfigManager            │
│  (KeyboardShortcuts) │ (TOMLKit + FS watcher) │
├──────────────────────────────────────────────┤
│  ActionDispatcher (Command pattern)          │
├──────────────────────────────────────────────┤
│  WindowController │ AppLauncher │ PreviewUI  │
│  (AX API wrapper) │ (NSWorkspace)│ (SwiftUI) │
├──────────────────────────────────────────────┤
│  AccessibilityClient (low-level AX wrapper)  │
└──────────────────────────────────────────────┘
```

### データフロー（半分分割の例）

```
ユーザがキー押下
  → HotkeyManager がイベント受信
  → ActionDispatcher が "snapToLeftHalf" を発火
  → PreviewUI がプレビューを表示（SwiftUI spring アニメ）
  → WindowController が AXEnhancedUserInterface を ON
  → 目標 frame を AX 経由でセット
  → AXEnhancedUserInterface を OFF
  → PreviewUI がフェードアウト
```

---

## 4. 設定ファイル設計

### 配置場所

```
~/.config/<appname>/config.toml
```

XDG 準拠で `XDG_CONFIG_HOME` を尊重。dotfiles で symlink するのが基本想定。

### スキーマ案

```toml
# ~/.config/wm/config.toml

[general]
animation_enabled = true
animation_duration = 0.25     # 秒
padding = 8                   # ウィンドウ間の隙間 (px)

[hotkeys]
# モディファイア表記: cmd, opt, ctrl, shift
focus_left   = "cmd+opt+left"
focus_right  = "cmd+opt+right"
focus_up     = "cmd+opt+up"
focus_down   = "cmd+opt+down"

snap_left    = "cmd+ctrl+left"
snap_right   = "cmd+ctrl+right"
snap_top     = "cmd+ctrl+up"
snap_bottom  = "cmd+ctrl+down"
maximize     = "cmd+ctrl+return"
center       = "cmd+ctrl+c"

# 1/4 分割
snap_top_left     = "cmd+ctrl+shift+left"
snap_top_right    = "cmd+ctrl+shift+right"
snap_bottom_left  = "cmd+opt+shift+left"
snap_bottom_right = "cmd+opt+shift+right"

[[launch]]
key = "cmd+shift+1"
bundle_id = "com.apple.Safari"

[[launch]]
key = "cmd+shift+2"
bundle_id = "com.googlecode.iterm2"

[[launch]]
key = "cmd+shift+3"
bundle_id = "com.microsoft.VSCode"
```

### ホットリロード方針

- ファイル変更検知 → 一度全ホットキー unregister → 再パース → 再 register
- パースエラーは menubar アイコンに通知バッジで提示し、旧設定を維持

---

## 5. 実装フェーズ

各 Phase は GitHub の milestone に対応させる想定。

### Phase 0: プロジェクトセットアップ（半日）

- Xcode プロジェクト作成 (`macOS App`, SwiftUI, Swift 5.9)
- `Info.plist` に `LSUIElement = YES`
- `NSAppleEventsUsageDescription` 追加
- `NSAccessibilityUsageDescription` 追加
- Swift Package Manager で依存追加
  - KeyboardShortcuts
  - TOMLKit
- GitHub リポジトリ初期化 + GitHub Actions の Xcode build CI 雛形

### Phase 1: コア・ウィンドウ操作（2〜3 日）

最優先で「動く最小版」を作る。アニメは後回し。

1. **アクセシビリティ権限フロー**
   - 起動時に `AXIsProcessTrustedWithOptions` でチェック
   - 未許可なら案内シートを表示 → 「設定を開く」ボタン
   - 許可後は再起動なしで動作するよう polling で監視

2. **`AccessibilityClient`**
   - フロントモストアプリ取得
   - そのアプリの focused window 取得
   - position / size / fullscreen 属性の get / set
   - エラーハンドリング（権限切れ、アプリ未対応など）

3. **`WindowController`** の基本アクション
   - `snapToLeftHalf()`, `snapToRightHalf()`
   - `snapToTopHalf()`, `snapToBottomHalf()`
   - `maximize()` (画面サイズ全体に拡大、メニューバー・Dock 領域を除く)
   - `center()`
   - `toggleFullscreen()` (`kAXFullScreenAttribute`)
   - 1/4 分割 4 種

4. **フォーカス移動**
   - 全ウィンドウのリストを座標ソートし、方向に応じて選択
   - 選ばれた window を `AXRaiseAction` でフロントへ

5. **ハードコードホットキーで動作確認**
   - この段階では config 読まず、`AppDelegate` でキーを直接登録

### Phase 2: 設定ファイル + ホットリロード（1〜2 日）

1. `Config` 構造体定義（Codable + TOMLKit）
2. デフォルト config を bundle 内 resource として持つ
3. 初回起動時に `~/.config/<appname>/config.toml` が無ければコピー
4. `ConfigManager` でロード・バリデーション・エラー表示
5. `DispatchSource` でファイル監視 → 変更で reload
6. `HotkeyManager` を config 駆動に書き換え

### Phase 3: アプリ起動ショートカット（半日）

1. config の `[[launch]]` セクションをパース
2. ホットキー押下で `NSWorkspace.shared.openApplication(at:configuration:)`
3. 既に起動済みなら最前面に activate するロジック
4. bundle id が見つからない場合のエラー処理

### Phase 4: アニメーション（3〜4 日 ← ここが本番）

Loop インスパイアの戦略：**プレビューウィンドウで「綺麗さ」を演出し、実ウィンドウは速攻スナップ**。

1. **`PreviewWindow`**
   - `NSPanel` (非アクティベート、非フォーカス、`.statusBar` レベル)
   - 内容は SwiftUI で半透明角丸 + 枠線
   - 表示時: `.scale + .opacity` の spring アニメ
   - スナップ先変更時: `withAnimation(.spring(response: 0.35, dampingFraction: 0.7))` で frame 更新
   - 確定時: フェードアウト

2. **`AnimationConstants.swift`** （Luminare 的役割）
   ```swift
   enum Anim {
       static let snapSpring   = Animation.spring(response: 0.35, dampingFraction: 0.75)
       static let previewFade  = Animation.easeOut(duration: 0.18)
       static let menuAppear   = Animation.spring(response: 0.28, dampingFraction: 0.8)
   }
   ```

3. **実ウィンドウのリサイズスムージング**
   - `AXEnhancedUserInterface = true` をセット → frame 変更 → false に戻す
   - Electron / Firefox / Notion で効果大
   - 一部アプリで副作用があるため bundle id ベースの除外リストを config に持てるようにする

4. **(任意) ウィンドウ移動の補間アニメ**
   - 開始 frame → 終了 frame を `CVDisplayLink` で 60/120fps 補間
   - easing は `easeOutCubic`
   - アプリ別 opt-out 設定を用意（重いアプリで切れるように）
   - **最初はオフ・デフォルトで様子を見る**

### Phase 5: 仕上げ（2〜3 日）

1. **MenuBarExtra UI**
   - 状態アイコン
   - 「設定」「config を開く」「config を reload」「Quit」
2. **設定画面**
   - SwiftUI で 1 画面
   - ホットキー記録 UI（KeyboardShortcuts 標準）
   - アニメ ON/OFF、padding 等のトグル
   - config ファイル一括編集はあくまで TOML を正とし、GUI は補助的
3. **アクセシビリティ権限の onboarding 画面**
4. **Sparkle 統合** + リリース署名 + notarization
5. **README / スクリーンショット / 配布**

---

## 6. 主要な技術課題と対策

### 6.1 アクセシビリティ権限

- 必須。`AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])` で初回プロンプト
- 許可状態は polling で監視（1Hz で十分）し、許可された瞬間に通常動作に遷移
- 「権限なし状態でも設定画面は開ける」UX 設計が重要

### 6.2 `AXEnhancedUserInterface` の使い方

```swift
func resize(window: AXUIElement, to frame: CGRect, in app: AXUIElement) {
    AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    defer {
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
    }
    // 位置・サイズを設定
    setPosition(window, frame.origin)
    setSize(window, frame.size)
}
```

注意点:
- 一部アプリ（Xcode 等）で副作用あり → 除外リストで運用
- 連続呼び出しのコストはそこまで高くない

### 6.3 マルチディスプレイ

- `NSScreen.screens` を尊重
- ウィンドウが属するスクリーンは、ウィンドウ中心座標で判定
- `visibleFrame` を使い、メニューバー・Dock 領域を除外

### 6.4 設定ホットリロード時の競合

- ファイル変更検知 → 100ms デバウンス → reload
- 一連の処理は main queue でシリアライズ

### 6.5 Loop と差別化する点（オリジナリティ）

- ラジアルメニューは作らず、**キーボード一本に振り切る**
- アプリ起動とウィンドウ操作を**同じホットキーレイヤで統一**
- 設定が TOML 一枚で完結（dotfiles 完全対応）

---

## 7. ディレクトリ構成

```
wm/
├── Package.swift                    # SPM dependency 管理
├── wm.xcodeproj/
├── wm/
│   ├── App/
│   │   ├── wmApp.swift           # @main, MenuBarExtra
│   │   ├── AppDelegate.swift
│   │   └── Onboarding/             # 権限案内
│   ├── Core/
│   │   ├── AccessibilityClient.swift
│   │   ├── WindowController.swift
│   │   ├── AppLauncher.swift
│   │   └── FocusNavigator.swift
│   ├── Hotkeys/
│   │   ├── HotkeyManager.swift
│   │   └── ActionDispatcher.swift
│   ├── Config/
│   │   ├── Config.swift            # Codable
│   │   ├── ConfigManager.swift     # load + watch
│   │   └── DefaultConfig.toml      # bundle resource
│   ├── UI/
│   │   ├── PreviewWindow.swift
│   │   ├── PreviewView.swift       # SwiftUI
│   │   ├── SettingsView.swift
│   │   └── AnimationConstants.swift
│   └── Util/
│       ├── Log.swift               # OSLog wrapper
│       └── Screen+Extensions.swift
├── wmTests/
└── README.md
```

---

## 8. 想定スケジュール

個人開発・週末ベースを想定（合計 7〜10 日 + アニメーション沼で +α）。

| Phase | 工数 | 累計 |
|---|---|---|
| 0. セットアップ | 0.5 日 | 0.5 |
| 1. コア機能 | 3 日 | 3.5 |
| 2. 設定ファイル | 2 日 | 5.5 |
| 3. アプリ起動 | 0.5 日 | 6 |
| 4. アニメーション | 4 日 | 10 |
| 5. 仕上げ | 3 日 | 13 |

実際には Phase 1 が動いた時点で日常使いを開始し、自分が困った順に Phase 2 以降を埋めていくのが現実的。

---

## 9. 参考資料

- [AeroSpace](https://github.com/nikitabobko/AeroSpace) — Swift 製 tiling WM。AX 周りの薄いラッパーと TOML スキーマが参考になる
- [Loop](https://github.com/MrKai77/Loop) — SwiftUI 全振りの設計、アニメーション値の集約方法
- [Luminare](https://github.com/MrKai77/Luminare) — Loop のデザインシステム本体（GPL v3 のため取り込みでなく**参考実装**として読む）
- [Rectangle](https://github.com/rxhanson/Rectangle) — AppKit ベースの定番。AX API の枯れた使い方が学べる
- [yabai](https://github.com/koekeishiya/yabai) — C 製で重い参考資料だが、ウィンドウ列挙・座標計算ロジックは普遍的
- Apple: [Accessibility Programming Guide](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/)

---

## 10. リスクと撤退ライン

- **Apple のセキュリティ強化**: AX API の仕様変更リスクは常にある（過去にも何度かある）。撤退ラインは「特定 macOS バージョンでクラッシュが頻発するようになったら、その OS をサポート対象外とする」
- **重いアプリでのカクつき**: Electron 系で `AXEnhancedUserInterface` でも改善しない場合は、当該アプリ専用の特別ハンドリングを config から指定できるようにする
- **アニメーション沼**: Phase 4 で時間が溶けがちなので、「プレビューウィンドウのアニメまで」で MVP リリースし、実ウィンドウ補間アニメは v1.1 送りにする決断を持つ
