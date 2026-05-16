import Foundation
import TOMLKit

// 設定ファイルのロード・監視・リロードを担当する。Phase 2 で本実装する。
final class ConfigManager {
    static let shared = ConfigManager()

    private(set) var current: Config = Config()

    // XDG_CONFIG_HOME を尊重して config パスを決定する
    static var configPath: URL {
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        let base: URL
        if let xdg, !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config")
        }
        return base.appendingPathComponent("mywm").appendingPathComponent("config.toml")
    }

    private init() {}

    // 起動時に呼ぶ。ファイルが無ければ bundle 内のデフォルトをコピーする
    func bootstrap() {
        // Phase 2: ensureDefaultConfig() → load() → startWatching() を呼ぶ
    }

    // ファイルを読み直して current を更新する
    func reload() {
        // Phase 2: TOMLDecoder で current を更新し、ホットキーを再登録する
    }

    // DispatchSource でファイル監視を開始する
    private func startWatching() {
        // Phase 2: DispatchSource.makeFileSystemObjectSource を使う
    }
}
