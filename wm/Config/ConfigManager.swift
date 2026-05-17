import Foundation
import TOMLKit

// 設定ファイルのロード・監視・リロードを担当する。
// シングルトン。Bootstrap 後は current から読み取る。
// DispatchSource は main queue で監視するため、main actor に固定する
@MainActor
final class ConfigManager {
    static let shared = ConfigManager()

    private(set) var current: Config = Config()

    // 設定変更時に呼ばれるコールバック。HotkeyManager から購読する
    var onChange: ((Config) -> Void)?

    // パースエラーなどを UI に伝えるためのプロパティ
    private(set) var lastError: String?

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
        return base.appendingPathComponent("wm").appendingPathComponent("config.toml")
    }

    private var fileSource: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?

    private init() {}

    // 起動時に呼ぶ。ファイルが無ければ bundle 内のデフォルトをコピーし、ロード後に監視を開始する
    func bootstrap() {
        ensureDefaultConfigExists()
        reload()
        startWatching()
    }

    // ファイルを読み直して current を更新する。エラー時は旧設定を維持
    func reload() {
        let path = Self.configPath
        do {
            let data = try Data(contentsOf: path)
            let text = String(data: data, encoding: .utf8) ?? ""
            let decoder = TOMLDecoder()
            let parsed = try decoder.decode(Config.self, from: text)
            current = parsed
            lastError = nil
            Log.config.info("config を読み込みました: \(path.path)")
            onChange?(parsed)
        } catch {
            lastError = String(describing: error)
            Log.config.error("config のパースに失敗: \(String(describing: error))")
        }
    }

    // ユーザーディレクトリに config が無ければ bundle 内のデフォルトをコピーする
    private func ensureDefaultConfigExists() {
        let path = Self.configPath
        let dir = path.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: path.path) { return }
        // bundle 内の DefaultConfig.toml を探してコピー
        if let bundled = Bundle.main.url(forResource: "DefaultConfig", withExtension: "toml") {
            do {
                try FileManager.default.copyItem(at: bundled, to: path)
                Log.config.info("デフォルト config をコピー: \(path.path)")
            } catch {
                Log.config.error("デフォルト config のコピーに失敗: \(String(describing: error))")
            }
        } else {
            // bundle に無ければ最小限の空 config を書き出す
            try? "".write(to: path, atomically: true, encoding: .utf8)
        }
    }

    // DispatchSource でファイル監視を開始する。100ms のデバウンス付き
    private func startWatching() {
        let path = Self.configPath
        let fd = open(path.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.config.error("config の監視用 fd が開けませんでした: \(path.path)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            // DispatchSource は main queue 指定なのでハンドラは main thread で呼ばれる
            MainActor.assumeIsolated {
                self?.scheduleReload()
                // delete / rename ではエディタが上書き保存した可能性が高いので、監視を貼り直す
                let flags = source.data
                if flags.contains(.delete) || flags.contains(.rename) {
                    self?.fileSource?.cancel()
                    self?.fileSource = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        MainActor.assumeIsolated {
                            self?.startWatching()
                        }
                    }
                }
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileSource = source
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }
}
