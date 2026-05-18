import Foundation

// TOML 設定ファイルのスキーマ。Codable + TOMLKit でデシリアライズする
// 全フィールドはオプショナル扱い。記述が無ければ default 値を使う
struct Config: Codable, Equatable {
    var general: General = General()
    var hotkeys: [String: String] = [:]
    var launch: [Launch] = []

    enum CodingKeys: String, CodingKey {
        case general
        case hotkeys
        case launch
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.general = try c.decodeIfPresent(General.self, forKey: .general) ?? General()
        self.hotkeys = try c.decodeIfPresent([String: String].self, forKey: .hotkeys) ?? [:]
        self.launch = try c.decodeIfPresent([Launch].self, forKey: .launch) ?? []
    }

    struct General: Codable, Equatable {
        var animationEnabled: Bool = true
        var animationDuration: Double = 0.25
        var padding: Int = 8
        // AXEnhancedUserInterface の副作用が出るアプリの bundle id を除外できるようにする
        var enhancedUIExcluded: [String] = []

        enum CodingKeys: String, CodingKey {
            case animationEnabled = "animation_enabled"
            case animationDuration = "animation_duration"
            case padding
            case enhancedUIExcluded = "enhanced_ui_excluded"
        }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.animationEnabled = try c.decodeIfPresent(Bool.self, forKey: .animationEnabled) ?? true
            self.animationDuration = try c.decodeIfPresent(Double.self, forKey: .animationDuration) ?? 0.25
            self.padding = try c.decodeIfPresent(Int.self, forKey: .padding) ?? 8
            self.enhancedUIExcluded = try c.decodeIfPresent([String].self, forKey: .enhancedUIExcluded) ?? []
        }
    }

    // bundle_id 指定の .app 起動と、path 指定の任意実行ファイル起動の両方を受け付ける。
    // どちらか片方が必須。両方指定された場合は bundle_id が優先される
    struct Launch: Codable, Equatable {
        var key: String
        var bundleId: String?
        var path: String?

        enum CodingKeys: String, CodingKey {
            case key
            case bundleId = "bundle_id"
            case path
        }
    }
}

// hotkeys キーから Action へのマッピング
extension Config {
    static func action(forHotkeyKey key: String) -> Action? {
        switch key {
        case "focus_left":        return .focus(.left)
        case "focus_right":       return .focus(.right)
        case "focus_up":          return .focus(.up)
        case "focus_down":        return .focus(.down)
        case "snap_left":         return .snapLeft
        case "snap_right":        return .snapRight
        case "snap_top":          return .snapTop
        case "snap_bottom":       return .snapBottom
        case "maximize":          return .maximize
        case "center":            return .center
        case "toggle_fullscreen": return .toggleFullscreen
        default:                  return nil
        }
    }
}
