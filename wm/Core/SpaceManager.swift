import AppKit
import ApplicationServices

// macOS の Spaces（仮想デスクトップ）を跨いだウィンドウ巡回サポート。
// AX の kAXWindowsAttribute は別 Space のウィンドウを返さないため、
// CGWindowList で全ウィンドウを取り、CGS の private API で各ウィンドウが
// 属する Space を判定する。Space 切り替えも CGS private API 経由で行う。
//
// 使っている関数は yabai / AeroSpace 等のウィンドウマネージャ実装と同じ系統で、
// 公開ヘッダには含まれないが macOS の SkyLight framework 内に存在する
enum SpaceManager {

    // MARK: - Private CGS / AX 関数の宣言

    typealias CGSConnectionID = Int32

    @_silgen_name("CGSMainConnectionID")
    static func CGSMainConnectionID() -> CGSConnectionID

    @_silgen_name("CGSCopySpacesForWindows")
    static func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ wids: CFArray) -> Unmanaged<CFArray>?

    @_silgen_name("CGSCopyManagedDisplaySpaces")
    static func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>?

    @_silgen_name("CGSManagedDisplaySetCurrentSpace")
    static func CGSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID, _ display: CFString, _ space: UInt64)

    @_silgen_name("_AXUIElementGetWindow")
    static func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

    // MARK: - 公開関数

    // 指定 pid の通常ウィンドウのうち、現在 focused のウィンドウとは別 Space にある
    // ものを 1 つ選び、その Space に切り替えてアプリを activate する。
    // 別 Space に他ウィンドウが見つからない場合は false
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

        // focused window の CGWindowID
        var focusedWID: CGWindowID = 0
        if let focused = focusedWindow {
            _ = _AXUIElementGetWindow(focused, &focusedWID)
        }

        let cid = CGSMainConnectionID()

        // focused の Space ID を取得（mask=7 = all spaces）
        let focusedSpaces = (focusedWID != 0)
            ? copySpaces(cid: cid, windowIDs: [focusedWID])
            : []
        let focusedSpaceID = focusedSpaces.first ?? 0
        Log.app.info("space cycle: focusedWID=\(focusedWID) focusedSpace=\(focusedSpaceID)")

        // focused 以外で別 Space にある最初のウィンドウを探す
        var targetWID: CGWindowID = 0
        var targetSpaceID: UInt64 = 0
        for wid in windowIDs where wid != focusedWID {
            let spaces = copySpaces(cid: cid, windowIDs: [wid])
            guard let sid = spaces.first else { continue }
            if sid != focusedSpaceID {
                targetWID = wid
                targetSpaceID = sid
                break
            }
        }
        guard targetSpaceID != 0 else {
            Log.app.info("space cycle: 別 Space のウィンドウなし")
            return false
        }
        Log.app.info("space cycle: targetWID=\(targetWID) targetSpace=\(targetSpaceID)")

        _ = targetWID

        // ターゲット Space のディスプレイと、同一ディスプレイ内の Space インデックス差分を計算する。
        // CGSManagedDisplaySetCurrentSpace は内部状態だけを書き換え、Mission Control の
        // アニメーションが走らず「現在 Space に別ウィンドウが現れた」ように見えるため、
        // 代わりに macOS 標準ショートカット Ctrl+← / Ctrl+→ を CGEvent で送出して
        // 必要回数だけ隣の Space へ移動する
        guard let displays = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else {
            return false
        }
        for d in displays {
            guard let spaces = d["Spaces"] as? [[String: Any]] else { continue }
            let ids = spaces.compactMap { $0["id64"] as? UInt64 }
            guard let targetIdx = ids.firstIndex(of: targetSpaceID),
                  let focusedIdx = ids.firstIndex(of: focusedSpaceID) else { continue }
            let diff = targetIdx - focusedIdx
            guard diff != 0 else { return false }
            let keyCode: CGKeyCode = diff > 0 ? 0x7C : 0x7B // 124=Right, 123=Left
            let count = abs(diff)
            Log.app.info("space cycle: ctrl+\(diff > 0 ? "→" : "←") x\(count)")
            for _ in 0..<count {
                postCtrlArrow(keyCode: keyCode)
            }
            return true
        }
        return false
    }

    // Ctrl 修飾子付きで指定キーを 1 回押す
    private static func postCtrlArrow(keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true) {
            down.flags = .maskControl
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            up.flags = .maskControl
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - 内部ヘルパー

    private static func copySpaces(cid: CGSConnectionID, windowIDs: [CGWindowID]) -> [UInt64] {
        let arr = windowIDs.map { NSNumber(value: $0) } as CFArray
        guard let result = CGSCopySpacesForWindows(cid, 7, arr)?.takeRetainedValue() as? [NSNumber] else {
            return []
        }
        return result.map { $0.uint64Value }
    }
}
