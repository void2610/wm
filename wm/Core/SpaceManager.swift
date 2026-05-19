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

        // ターゲット Space を含むディスプレイを見つけて切り替える。
        // activate は呼ばない — 別 Space のウィンドウが現在 Space に引きずり込まれるため。
        // Space 切り替え後は AX kAXWindowsAttribute からも対象ウィンドウが見えるので、
        // 短い遅延を入れて改めて AX 経由で raise する
        guard let displays = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else {
            return false
        }
        var switched = false
        for d in displays {
            guard let displayID = d["Display Identifier"] as? String,
                  let spaces = d["Spaces"] as? [[String: Any]] else { continue }
            for s in spaces {
                guard let sid = s["id64"] as? UInt64, sid == targetSpaceID else { continue }
                CGSManagedDisplaySetCurrentSpace(cid, displayID as CFString, targetSpaceID)
                Log.app.info("space cycle: switched display=\(displayID) -> space=\(targetSpaceID)")
                switched = true
                break
            }
            if switched { break }
        }
        guard switched else { return false }

        // Space 切り替え直後は AX 側の windows 一覧が古いことがあるので、次の runloop で raise
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            raiseAXWindow(pid: pid, matching: targetWID)
        }
        return true
    }

    // 指定 pid の AX ウィンドウ一覧から CGWindowID が一致するものを探して raise する
    private static func raiseAXWindow(pid: pid_t, matching wid: CGWindowID) {
        let app = AXUIElementCreateApplication(pid)
        for w in AccessibilityClient.windows(of: app) {
            var thisWID: CGWindowID = 0
            guard _AXUIElementGetWindow(w, &thisWID) == .success, thisWID == wid else { continue }
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            _ = AccessibilityClient.raise(w)
            Log.app.info("space cycle: AX raise wid=\(wid)")
            return
        }
        Log.app.info("space cycle: AX 側に wid=\(wid) が見つからず raise 省略")
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
