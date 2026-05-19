import AppKit
import ApplicationServices

// 低レベル AX API のラッパー。
// フロントモストアプリ・focused window の取得、position/size/fullscreen 属性の get/set、
// AXEnhancedUserInterface のトグル、権限状態のチェックを提供する。
enum AccessibilityClient {

    // MARK: - 権限

    // アクセシビリティ権限の状態をチェックする。prompt = true で初回プロンプトを出す。
    // ポーリングで使う通常チェックは AXIsProcessTrusted() を直接呼ぶ。
    // AXIsProcessTrustedWithOptions(prompt:false) はプロセス内で値がキャッシュされる
    // ケースがあり、許可後も false を返し続けることがあるため初回プロンプト時のみ使う。
    static func isTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let options: CFDictionary = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    // MARK: - アプリ / ウィンドウ取得

    // 最前面アプリの AXUIElement と pid を返す
    static func frontmostApp() -> (element: AXUIElement, pid: pid_t)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return (element, app.processIdentifier)
    }

    // 最前面アプリの focused window を返す
    static func focusedWindow() -> AXUIElement? {
        guard let app = frontmostApp() else { return nil }
        return focusedWindow(of: app.element)
    }

    // 指定アプリの focused window を返す
    static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let window = value else { return nil }
        return (window as! AXUIElement)
    }

    // 指定アプリの全ウィンドウ配列を返す
    static func windows(of app: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let array = value as? [AXUIElement] else { return [] }
        return array
    }

    // 起動中の全アプリの全ウィンドウを集めて返す
    static func allWindows() -> [(window: AXUIElement, app: AXUIElement)] {
        var result: [(AXUIElement, AXUIElement)] = []
        for runningApp in NSWorkspace.shared.runningApplications where runningApp.activationPolicy == .regular {
            let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
            for window in windows(of: appElement) {
                result.append((window, appElement))
            }
        }
        return result
    }

    // MARK: - 属性 get/set

    // ウィンドウの位置を取得する（screen 座標、左上原点）
    static func getPosition(_ window: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value)
        guard result == .success else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    // ウィンドウのサイズを取得する
    static func getSize(_ window: AXUIElement) -> CGSize? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value)
        guard result == .success else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }

    // ウィンドウの位置をセットする
    @discardableResult
    static func setPosition(_ window: AXUIElement, _ point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    // ウィンドウのサイズをセットする
    @discardableResult
    static func setSize(_ window: AXUIElement, _ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    // ウィンドウの frame（位置 + サイズ）をまとめてセットする。
    //
    // macOS の Window Tiling 等で「最大化に近い」状態のウィンドウに対しては、
    // 単発の setSize / setPosition だと システム側で 元 frame に強制復元される
    // ことがある（setSize で size 反映 → 次の setPosition 時に size を 元値に巻き戻し、
    // setPosition で pos 反映 → 次の setSize 時に pos を 元値に巻き戻す、の振動）。
    //
    // これを抑止するため、setFrame は app 引数を取る setFrameWithApp 版を使う。
    // 後方互換のためのオーバーロード。
    static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        setSize(window, frame.size)
        setPosition(window, frame.origin)
        setSize(window, frame.size)
    }

    // app に AXEnhancedUserInterface = true を一時的に立てて AX 操作を行うと、
    // 操作中はアプリ側の自動補正（Window Tiling の復元処理など）が走らず
    // setSize / setPosition の打ち消し合いを回避できる。
    // 操作後に必ず元の値に戻す。
    static func setFrame(_ window: AXUIElement, app: AXUIElement, _ frame: CGRect) {
        let enhancedKey = "AXEnhancedUserInterface" as CFString
        var current: AnyObject?
        AXUIElementCopyAttributeValue(app, enhancedKey, &current)
        let wasEnabled = (current as? Bool) ?? false

        // Enhanced UI が ON の状態だと AX 経由の setSize / setPosition がアプリ内で
        // バッチ化・遅延されてしまい、片方しか反映されない（setSize は通るが
        // setPosition は無視されるなど）。操作中は必ず OFF にしてから set し、
        // 終わったら元の状態に戻す。
        if wasEnabled {
            AXUIElementSetAttributeValue(app, enhancedKey, kCFBooleanFalse)
        }

        setSize(window, frame.size)
        setPosition(window, frame.origin)
        setSize(window, frame.size)

        if wasEnabled {
            AXUIElementSetAttributeValue(app, enhancedKey, kCFBooleanTrue)
        }

        // 反映確認ログ
        let pos = getPosition(window) ?? .zero
        let size = getSize(window) ?? .zero
        Log.window.info("setFrame(wasEnabled=\(wasEnabled)) target=\(String(describing: frame), privacy: .public) actual pos=\(String(describing: pos), privacy: .public) size=\(String(describing: size), privacy: .public)")
    }

    // ウィンドウの frame を取得する
    static func getFrame(_ window: AXUIElement) -> CGRect? {
        guard let origin = getPosition(window), let size = getSize(window) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    // フルスクリーン状態を取得する
    static func isFullscreen(_ window: AXUIElement) -> Bool {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
        guard result == .success, let bool = value as? Bool else { return false }
        return bool
    }

    // フルスクリーン状態をトグルする
    static func toggleFullscreen(_ window: AXUIElement) {
        let current = isFullscreen(window)
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, !current as CFTypeRef)
    }

    // ウィンドウをフロントに上げる
    @discardableResult
    static func raise(_ window: AXUIElement) -> Bool {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    }

    // MARK: - AXEnhancedUserInterface

    // ウィンドウの frame をセットする（アプリ向け）。
    // 旧版では AXEnhancedUserInterface を ON にして連続リサイズのカクつきを抑える
    // 設計だったが、ON 中に setSize / setPosition を複数回呼ぶとアプリ側でバッチ化
    // されて順序が崩れる症状（上半分→右半分のときに高さが halfH のまま下半分に
    // 降りる、等）があったため、現状は使用しない。スムージングは後日 opt-in で再導入する。
    // 引数の skipEnhancedFor / excluded は将来のために残してあるが現状未使用。
    static func setFrameSmoothing(
        window: AXUIElement,
        app: AXUIElement,
        frame: CGRect,
        skipEnhancedFor bundleId: String? = nil,
        excluded: Set<String> = []
    ) {
        _ = bundleId
        _ = excluded
        setFrame(window, app: app, frame)
    }
}
