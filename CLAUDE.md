# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

macOS 向けキーボード中心のウィンドウマネージャ。AeroSpace ライクな機能セット + Loop ライクなアニメーション品質を狙う個人プロジェクト。menu bar 常駐アプリ（Dock 非表示）、TOML 設定。Bundle ID: `com.void2610.wm`。

## ビルド・実行

Xcode プロジェクトは xcodegen で生成する（`.xcodeproj` は gitignore 対象）。

```sh
# 依存追加・project.yml 変更時に再生成
nix-shell -p xcodegen --run "xcodegen generate --spec project.yml"

# Debug ビルド
xcodebuild -project wm.xcodeproj -scheme wm -configuration Debug \
  -destination "platform=macOS" -derivedDataPath build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

# ローカル起動（entitlements を有効にするため ad-hoc 署名が必要）
codesign --force --deep --sign - build/Build/Products/Debug/wm.app
open build/Build/Products/Debug/wm.app

# テスト
xcodebuild -project wm.xcodeproj -scheme wm -configuration Debug \
  -destination "platform=macOS" -derivedDataPath build test
```

CI（`.github/workflows/ci.yml`）は `macos-15` ランナーで Debug ビルド・テスト・Release の ad-hoc 署名済み `.app` を artifact `wm-<short-sha>.zip` としてアップロードする。Release ビルドでは `CODE_SIGN_IDENTITY="-"` を必ず付ける — `CODE_SIGNING_ALLOWED=NO` で未署名にすると quarantine 付き起動時に App Translocation の対象になる。

## アーキテクチャ

```
┌──────────────────────────────────────────────┐
│  App (LSUIElement, NSStatusItem)             │
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

操作は `Action` enum（`wm/Hotkeys/ActionDispatcher.swift`）に集約されている。新しい操作を追加するときは Action に case を足し、ActionDispatcher で `WindowController` / `AppLauncher` のメソッドにディスパッチする。ホットキー名（`snap_top` 等）から Action へのマッピングは `Config.action(forHotkeyKey:)` にある。

## 重要な実装上の注意

### menu bar 常駐構成

- Info.plist で `LSUIElement=YES` を立てている。SwiftUI App は `WindowGroup` を 1 つ持つが `HiddenLifecycleView` で即座に閉じるダミー。
- menu bar item は MenuBarExtra ではなく `AppDelegate.setupStatusItem()` で `NSStatusItem` を直接生成している。MenuBarExtra + LSUIElement の組合せはアイコンが表示されない症状があったため避ける。
- `setActivationPolicy(.accessory)` はランタイムでは呼ばない（LSUIElement で十分）。ランタイム切替は Dock に一瞬出る問題がある。

### 座標系

AX API と NSScreen で座標系が違う。`wm/Util/Screen+Extensions.swift` の変換ユーティリティを必ず通すこと。

- AppKit (NSScreen): primary display の左下が原点、Y 上方向
- Accessibility API: primary display の左上が原点、Y 下方向
- スナップ枠は `NSScreen.leftHalf(padding:)` 等で NSScreen 座標で計算 → `NSScreen.convertToAX()` で AX 座標に変換してウィンドウに適用

### AX setFrame の順序と AXEnhancedUserInterface

`AccessibilityClient.setFrame` は `setSize → setPosition → setSize` の順で 2 回 size をセットしている。`setPosition → setSize` の順だと「上半分（全幅×半高）→右半分（半幅×全高）」のように移動と縮小を同時にやるケースで、1 回目の setPosition が画面外にはみ出して macOS にクランプされてしまうため。この順序を変えないこと。

更に、app 引数を取る `setFrame(window:app:_:)` 版では **操作中だけ `AXEnhancedUserInterface` を強制 OFF にし、終わったら元の値に戻す** ようにしている。ターゲットアプリがすでに Enhanced UI を ON にしていると AX 経由の setSize / setPosition がアプリ内でバッチ化・遅延され、setSize は通るが setPosition が無視される（snap 右で size のみ縮み pos は左端のまま）症状が出るため。`WindowController` は必ず `setFrameSmoothing` 経由で app 付き版を呼ぶ。

### プレビューウィンドウのアニメーション

`wm/UI/PreviewWindow.swift` は **NSPanel をスナップ対象スクリーン 1 枚分にして show 時のみ orderFrontRegardless**、中の矩形を SwiftUI の `@Published rect` で補間する設計。フェード in/out と スライドを **別レイヤーに分離している点が肝**。次の罠を踏まないために以下を守ること:

- フェード in/out は `panel.alphaValue` を **自前 Timer で 60Hz 補間** する。SwiftUI の `.opacity` / `withAnimation` は連続 show / hide のタイミングで補間状態をリセットしにくく、「アニメが終わった直後に次が始まると途中からしか見えない」症状を踏む。`NSWindow.animator().alphaValue` も CAAnimation が backing layer に attach されて `contentView.layer.removeAllAnimations()` では止められないため、自前 Timer で `invalidate()` ベースの確実な停止を可能にしている。
- スライド（rect 補間）は SwiftUI 側で `withAnimation(.easeOut(duration: animationDuration))` を使う。spring は終端時刻が不確定で `autoHideAfter` と衝突するので使わない。
- `NSWindow.animator().setFrame` は使わない。連続呼出時に AppKit のアニメ状態が不安定で、2 回目以降のアニメが走らなくなることがある。
- 初回出現時は `withTransaction(disablesAnimations)` で rect を `from` に瞬間配置してから、`DispatchQueue.main.asyncAfter(deadline: .now() + 2/60)` で次の描画フレームを待ってから target へ移行する。同じ tick で 2 回 rect を更新すると SwiftUI が中間状態を render しないため、from→target のスライドが見えなくなる。
- **`hide()` 完了後の `orderOut` は 2 秒遅延させる**。直後に orderOut すると次の show での `orderFrontRegardless` 〜 最初の描画フレームに遅延が出てフェードインの先頭が見えなくなる。連続 show 時には `orderOutWorkItem.cancel()` で遅延 orderOut を取り消し、panel は alpha=0 のまま visible で残す。2 秒経って show が来なければ orderOut して Dock 自動非表示の抑制を解除する。
- フェードアウト進行中（alpha が中間値）に show が来た場合は、**alpha を 0 にリセットせず現在値から 1 に「中断・反転」させる**。panel に切れ目が出ず自然に繋がる。
- `PreviewView` には `.id(viewModel.generation)` を付与し、show 毎に generation を inc して view ツリーを再生成、SwiftUI の補間器・@State を完全リセットする。
- `viewModel.overlayFrame` は panel を貼ったスクリーンの visibleFrame。SwiftUI 側で rect をパネル内ローカル座標に変換するのに使う。

### TOML 設定の decoder

`Config` / `Config.General` は手書きの `init(from:)` を持っていて `decodeIfPresent` で欠落キーに default を割り当てる。Swift の合成 init は default 値があっても missing key で throw するため、新フィールドを追加するときは必ずこのパターンを踏襲する。

### TCC（アクセシビリティ権限）

`PermissionMonitor` は `AXIsProcessTrusted()` を 1Hz でポーリングする。`AXIsProcessTrustedWithOptions(prompt:false)` はプロセス内でキャッシュされて許可後も false を返し続けるケースがあるため初回プロンプト時のみ使う。Bundle ID を変更すると TCC エントリがリセットされて再許可が必要になる。

### ビルド時の git commit hash 埋め込み

`project.yml` の `postBuildScripts` で `git rev-parse --short HEAD` の結果を **ビルド成果物の `Info.plist` の `GitCommitHash` キーに書き込む**（ソース側 `wm/Info.plist` は触らない）。`SettingsView` の about タブで読み出して GitHub の commit ページへのリンクとして表示する。

incremental build で skip されないように、`inputFiles` に `$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)` を指定して `ProcessInfoPlistFile` に依存させている。これがないと `alwaysOutOfDate` 指定だけでは target up-to-date 判定で skip されることがある。

## ロギング

`Log.app` / `Log.window` 等の OSLog wrapper を使う（`wm/Util/Log.swift`）。実行中のログは:

```sh
log stream --predicate 'subsystem == "com.void2610.wm"' --info
```

## コーディング規約

- コメント・ログ文字列は日本語で記述する。
- Swift Concurrency: 全体的に `SWIFT_STRICT_CONCURRENCY=minimal`。AX / NSWorkspace / PreviewWindow を触る型（`WindowController`, `ConfigManager`, `HotkeyManager` 等）は `@MainActor` 固定。DispatchSource / asyncAfter のコールバック内では `MainActor.assumeIsolated { ... }` で main isolated にする。
