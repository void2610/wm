import AppKit
import ApplicationServices

// macOS の Spaces（仮想デスクトップ）を跨いだ同アプリウィンドウへの巡回サポート。
//
// 設計方針:
// - macOS には Space を programmatic に activate する公式 API が無い。
//   yabai は dock swipe gesture の合成、AeroSpace は macOS Spaces 自体を諦めて
//   独自 workspace を実装している。本プロジェクトでは AppleScript 経由で
//   Mission Control 標準ショートカット (Ctrl+←/→) を発火させる方式を採る。
// - CGSManagedDisplaySetCurrentSpace は「内部状態のみ書換」で Mission Control の
//   合成状態と不整合を起こし、フルスクリーン Space の描画バッファが現在 Space に
//   重なる破壊的挙動が出るため使わない。
// - 目的 Space が通常 Space（CGSCopyManagedDisplaySpaces に列挙される）の場合のみ
//   差分インデックスを計算してキー送出。フルスクリーン Space は列挙されないので
//   その場合はこの関数は false を返し、呼び出し側で通常の activate にフォールバックする
enum SpaceManager {

    // MARK: - Private CGS / AX 関数の宣言

    typealias CGSConnectionID = Int32

    @_silgen_name("CGSMainConnectionID")
    static func CGSMainConnectionID() -> CGSConnectionID

    @_silgen_name("CGSCopySpacesForWindows")
    static func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ wids: CFArray) -> Unmanaged<CFArray>?

    @_silgen_name("CGSCopyManagedDisplaySpaces")
    static func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>?

    @_silgen_name("_AXUIElementGetWindow")
    static func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

    // MARK: - 公開関数

    // 指定 pid の通常ウィンドウのうち、現在 focused のウィンドウとは別 Space にある
    // ものを 1 つ選び、その Space に切り替える。Mission Control 標準ショートカット
    // (Ctrl+←/→) を AppleScript で発火させてアニメーション付きで遷移する。
    // 目的 Space がフルスクリーン Space（managed display に列挙されない）の場合は
    // false を返し、呼び出し側に通常 activate フォールバックを促す
    static func cycleToAnotherSpaceWindow(pid: pid_t, focusedWindow: AXUIElement?) -> Bool {
        // 対象 pid の通常ウィンドウ（layer 0）を CGWindowList から全件取得
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let windowIDs: [CGWindowID] = info.compactMap { dict in
            guard let owner = dict[kCGWindowOwnerPID as String] as? pid_t, owner == pid else { return nil }
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            return dict[kCGWindowNumber as String] as? CGWindowID
        }
        Log.app.info("space cycle: pid=\(pid) windowIDs=\(windowIDs)")
        guard windowIDs.count >= 2 else { return false }

        var focusedWID: CGWindowID = 0
        if let focused = focusedWindow {
            _ = _AXUIElementGetWindow(focused, &focusedWID)
        }

        let cid = CGSMainConnectionID()
        let focusedSpaces = (focusedWID != 0)
            ? copySpaces(cid: cid, windowIDs: [focusedWID])
            : []
        let focusedSpaceID = focusedSpaces.first ?? 0
        Log.app.info("space cycle: focusedWID=\(focusedWID) focusedSpace=\(focusedSpaceID)")

        // focused 以外で別 Space にある最初のウィンドウを探す
        var targetSpaceID: UInt64 = 0
        for wid in windowIDs where wid != focusedWID {
            let spaces = copySpaces(cid: cid, windowIDs: [wid])
            guard let sid = spaces.first else { continue }
            if sid != focusedSpaceID {
                targetSpaceID = sid
                break
            }
        }
        guard targetSpaceID != 0 else {
            Log.app.info("space cycle: 別 Space のウィンドウなし")
            return false
        }
        Log.app.info("space cycle: targetSpace=\(targetSpaceID)")

        // managed display を走査して、focused と target が同じディスプレイ内の通常 Space
        // として並んでいるかを判定する。両方そろわなければフルスクリーン Space の可能性が高く、
        // この巡回方式は使えないので false を返す
        guard let displays = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else {
            return false
        }
        for d in displays {
            guard let spaces = d["Spaces"] as? [[String: Any]] else { continue }
            let ids = spaces.compactMap { $0["id64"] as? UInt64 }
            // OSLog で配列を直に補間するとマスクされるため、各要素を joined した数値文字列で出す
            let idsLog = ids.map { String($0) }.joined(separator: ",")
            Log.app.info("space cycle: display ids=[\(idsLog)] count=\(ids.count)")
            guard let targetIdx = ids.firstIndex(of: targetSpaceID),
                  let focusedIdx = ids.firstIndex(of: focusedSpaceID) else { continue }
            let diff = targetIdx - focusedIdx
            guard diff != 0 else { return false }
            Log.app.info("space cycle: dockSwipe diff=\(diff) focusedIdx=\(focusedIdx) targetIdx=\(targetIdx) ids.count=\(ids.count)")
            sendDockSwipe(diff: diff)
            return true
        }
        Log.app.info("space cycle: target が managed display に未登録（フルスクリーン Space の可能性）")
        return false
    }

    // MARK: - 内部ヘルパー

    private static func copySpaces(cid: CGSConnectionID, windowIDs: [CGWindowID]) -> [UInt64] {
        let arr = windowIDs.map { NSNumber(value: $0) } as CFArray
        guard let result = CGSCopySpacesForWindows(cid, 7, arr)?.takeRetainedValue() as? [NSNumber] else {
            return []
        }
        return result.map { $0.uint64Value }
    }

    // yabai 方式の dock swipe gesture を CGEvent で合成して Space を切り替える。
    // Mission Control の Ctrl+←/→ ショートカットはユーザー設定で無効化されている可能性が
    // あり、AppleScript で key code を送っても system が Space 切替として解釈しない
    // ケースがある。dock swipe は OS が直接 listen している low-level なイベントなので
    // ユーザー設定に依存しない。
    //
    // yabai/src/space_manager.c の space_manager_focus_space_using_gesture 相当。
    // 1 イベントを作って、phase 1 (began) と 4 (ended) を count 回ペアで post する
    private static func sendDockSwipe(diff: Int) {
        guard let event = CGEvent(source: nil) else { return }
        let sign: Double = diff > 0 ? 1.0 : -1.0
        let count = abs(diff)

        // kCGSEventDockControl 種別と kIOHIDEventTypeDockSwipe を示す private field
        event.setIntegerValueField(CGEventField(rawValue: 55), value: 30)
        event.setIntegerValueField(CGEventField(rawValue: 110), value: 23)
        event.setIntegerValueField(CGEventField(rawValue: 123), value: 1)
        event.setDoubleValueField(CGEventField(rawValue: 124), value: sign)
        event.setDoubleValueField(CGEventField(rawValue: 129), value: sign * 9999.0)

        for _ in 0..<count {
            // phase: began
            event.setIntegerValueField(CGEventField(rawValue: 132), value: 1)
            event.post(tap: .cgSessionEventTap)
            // phase: ended
            event.setIntegerValueField(CGEventField(rawValue: 132), value: 4)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
