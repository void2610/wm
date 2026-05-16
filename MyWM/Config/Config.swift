import Foundation

// TOML 設定ファイルのスキーマ。Codable + TOMLKit でデシリアライズする
struct Config: Codable, Equatable {
    var general: General = General()
    var hotkeys: [String: String] = [:]
    var launch: [Launch] = []

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
    }

    struct Launch: Codable, Equatable {
        var key: String
        var bundleId: String

        enum CodingKeys: String, CodingKey {
            case key
            case bundleId = "bundle_id"
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
        case "snap_top_left":     return .snapTopLeft
        case "snap_top_right":    return .snapTopRight
        case "snap_bottom_left":  return .snapBottomLeft
        case "snap_bottom_right": return .snapBottomRight
        case "maximize":          return .maximize
        case "center":            return .center
        case "toggle_fullscreen": return .toggleFullscreen
        default:                  return nil
        }
    }
}
