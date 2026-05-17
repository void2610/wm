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

操作は `Action` enum（`wm/Hotkeys/ActionDispatcher.swift`）に集約されている。新しい操作を追加するときは Action に case を足し、ActionDispatcher で `WindowController` / `AppLauncher` / `FocusNavigator` のメソッドにディスパッチする。ホットキー名（`snap_top` 等）から Action へのマッピングは `Config.action(forHotkeyKey:)` にある。

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

### AX setFrame の順序

`AccessibilityClient.setFrame` は `setSize → setPosition → setSize` の順で 2 回 size をセットしている。`setPosition → setSize` の順だと「上半分（全幅×半高）→右半分（半幅×全高）」のように移動と縮小を同時にやるケースで、1 回目の setPosition が画面外にはみ出して macOS にクランプされ、結果として左半分になってしまうため。この順序を変えないこと。

`AXEnhancedUserInterface` の自動トグルは現状無効化されている（`setFrameSmoothing` は `setFrame` を呼ぶだけ）。ON にすると複数の AX 操作がアプリ側でバッチ化されて順序が崩れる症状（上→右で右下 1/4 になる等）が出るため。

### プレビューウィンドウのアニメーション

`wm/UI/PreviewWindow.swift` は **NSPanel を全スクリーン union に固定して常時 visible**、中の矩形を SwiftUI の `@Published rect` で補間する設計。次の罠を踏まないために以下を守ること:

- `NSWindow.animator().setFrame` は使わない。連続呼出時に AppKit のアニメ状態が不安定で、2 回目以降のアニメが走らなくなることがある。
- アニメーションは `Anim.snapSlide(duration:)` の `easeOut(duration: ConfigManager.shared.current.general.animationDuration)` を使う。spring は終端時刻が不確定で `autoHideAfter` のタイミングと衝突する。`autoHideAfter == animationDuration` でスライド完走と同時にフェード退出が始まる確定的タイムラインを保つこと。
- 退出は `.opacity` のみで行う。`.transition(.scale)` を使うと anchor が view 自身ではなく layout frame 原点基準で解釈され、画面端の矩形が左上に向かってスライドして見える挙動になる。scale を再導入したい場合は `.offset` ベースの配置を `.position` ベースに変える必要がある。
- 初回出現時は `withTransaction(disablesAnimations)` で rect を `from` に瞬間配置してから、`DispatchQueue.main.async` で次の runloop tick に target へ移行する。同じ tick で 2 回 rect を更新すると SwiftUI が中間状態を render しないため、from→target のスライドが見えなくなる。

### TOML 設定の decoder

`Config` / `Config.General` は手書きの `init(from:)` を持っていて `decodeIfPresent` で欠落キーに default を割り当てる。Swift の合成 init は default 値があっても missing key で throw するため、新フィールドを追加するときは必ずこのパターンを踏襲する。

### TCC（アクセシビリティ権限）

`PermissionMonitor` は `AXIsProcessTrusted()` を 1Hz でポーリングする。`AXIsProcessTrustedWithOptions(prompt:false)` はプロセス内でキャッシュされて許可後も false を返し続けるケースがあるため初回プロンプト時のみ使う。Bundle ID を変更すると TCC エントリがリセットされて再許可が必要になる。

## ロギング

`Log.app` / `Log.window` 等の OSLog wrapper を使う（`wm/Util/Log.swift`）。実行中のログは:

```sh
log stream --predicate 'subsystem == "com.void2610.wm"' --info
```

## コーディング規約

- コメント・ログ文字列は日本語で記述する。
- Swift Concurrency: 全体的に `SWIFT_STRICT_CONCURRENCY=minimal`。AX / NSWorkspace / PreviewWindow を触る型（`WindowController`, `ConfigManager`, `HotkeyManager` 等）は `@MainActor` 固定。DispatchSource / asyncAfter のコールバック内では `MainActor.assumeIsolated { ... }` で main isolated にする。
