import Foundation

/// 设备登录返回码解析
/// 实测（LG6121F RP0204）：
///   "0|3"  → 成功（0 表示成功，3 是权限等级）
///   "4|0"  → 用户名或密码错误
///   "2|"   → 服务器忙/参数错误（不含sessionid等）
///   "3|"   → 会话过期
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
        case .busy:               return "设备繁忙，请稍后重试"
        case .sessionExpired:     return "会话已过期，请重试"
        case .unknown(let s):     return "登录失败（" + String(s.prefix(30)) + "）"
        }
    }
}
