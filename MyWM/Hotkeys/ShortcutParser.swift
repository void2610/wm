import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

// "cmd+ctrl+left" のような TOML 文字列を KeyboardShortcuts.Shortcut へ変換する。
// 失敗時は nil。エラーの詳細は呼び出し側で別途ログに残す。
enum ShortcutParser {

    enum ParseError: Error, CustomStringConvertible {
        case empty
        case unknownToken(String)
        case missingKey

        var description: String {
            switch self {
            case .empty: return "ショートカット文字列が空です"
            case .unknownToken(let s): return "未対応のキー指定: \(s)"
            case .missingKey: return "モディファイア以外のキーが指定されていません"
            }
        }
    }

    static func parse(_ string: String) -> KeyboardShortcuts.Shortcut? {
        try? parseStrict(string)
    }

    static func parseStrict(_ string: String) throws -> KeyboardShortcuts.Shortcut {
        let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { throw ParseError.empty }

        let tokens = trimmed.split(whereSeparator: { "+- ".contains($0) }).map(String.init)
        var carbonMods: Int = 0
        var keyCode: Int?

        for token in tokens {
            switch token {
            case "cmd", "command", "meta", "super":
                carbonMods |= cmdKey
            case "opt", "option", "alt":
                carbonMods |= optionKey
            case "ctrl", "control":
                carbonMods |= controlKey
            case "shift":
                carbonMods |= shiftKey
            default:
                if keyCode != nil {
                    throw ParseError.unknownToken(token)
                }
                guard let code = keyCodeForName(token) else {
                    throw ParseError.unknownToken(token)
                }
                keyCode = code
            }
        }

        guard let code = keyCode else { throw ParseError.missingKey }
        guard let shortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: code, carbonModifiers: carbonMods) else {
            throw ParseError.missingKey
        }
        return shortcut
    }

    // MARK: - 名前 → Carbon key code

    private static func keyCodeForName(_ name: String) -> Int? {
        if let mapped = nameToKeyCode[name] {
            return mapped
        }
        // 1 文字のアルファベット / 数字なら letter テーブルを参照
        if name.count == 1, let code = singleCharToKeyCode[name] {
            return code
        }
        return nil
    }

    private static let nameToKeyCode: [String: Int] = [
        // アルファベット
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        // 数字
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        // 矢印
        "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "up": kVK_UpArrow, "down": kVK_DownArrow,
        // 特殊キー
        "return": kVK_Return, "enter": kVK_Return,
        "tab": kVK_Tab, "space": kVK_Space, "esc": kVK_Escape, "escape": kVK_Escape,
        "delete": kVK_Delete, "backspace": kVK_Delete,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        // 記号
        "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal,
        "slash": kVK_ANSI_Slash, "backslash": kVK_ANSI_Backslash,
        "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period,
        "semicolon": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote,
        "leftbracket": kVK_ANSI_LeftBracket, "rightbracket": kVK_ANSI_RightBracket,
        // F キー
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
        "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
        "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]

    private static let singleCharToKeyCode: [String: Int] = nameToKeyCode
}
