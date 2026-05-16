import AppKit
import ApplicationServices

// 低レベル AX API のラッパー。フロントモストアプリ・focused window の取得や、
// position / size / fullscreen 属性の get / set を提供する想定。
// Phase 1 で本実装する。
enum AccessibilityClient {
    // アクセシビリティ権限の状態をチェックする
    static func isTrusted(prompt: Bool = false) -> Bool {
        let options: CFDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
