import Foundation

// TOML 設定ファイルのスキーマ。Codable + TOMLKit でデシリアライズする。
// Phase 2 で本実装する。
struct Config: Codable, Equatable {
    var general: General = General()
    var hotkeys: [String: String] = [:]
    var launch: [Launch] = []

    struct General: Codable, Equatable {
        var animationEnabled: Bool = true
        var animationDuration: Double = 0.25
        var padding: Int = 8

        enum CodingKeys: String, CodingKey {
            case animationEnabled = "animation_enabled"
            case animationDuration = "animation_duration"
            case padding
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
