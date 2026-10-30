import Foundation

/// 设备登录返回码解析
/// 实测（LG6121F RP0204，逐个测试确认）：
///   "0|3"  → 成功（0=成功，3=权限等级）
///   "4|0"  → 用户名或密码错误（第 1 次错误）
///   "2|"   → 已锁定（连续错误 2 次后触发，正确密码也会返回 2|）
///   "3|"   → 会话过期
/// ⚠ 锁定期间无法通过等待解除，需重启设备
enum LoginCode {
    case ok
    case badCredentials
    case busy
    case sessionExpired
    case unknown(String)

    static func parse(_ raw: String) -> LoginCode {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("0|") { return .ok }
        if t.hasPrefix("4|") { return .badCredentials }
        if t.hasPrefix("2|") { return .busy }
        if t.hasPrefix("3|") { return .sessionExpired }
        return .unknown(t)
    }

    var message: String {
        switch self {
        case .ok:                 return ""
        case .badCredentials:     return "用户名或密码错误"
        case .busy:               return "登录已锁定：请重启 CPE 设备后再试（等待无效）"
        case .sessionExpired:     return "会话已过期，请重试"
        case .unknown(let s):     return "登录失败（" + String(s.prefix(30)) + "）"
        }
    }
}
