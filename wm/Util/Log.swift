import OSLog

// OSLog の薄いラッパー。Console.app で `subsystem == "com.void2610.wm"` で絞り込める
enum Log {
    private static let subsystem = "com.void2610.wm"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
