import Foundation

/// CPE 厂商
enum CpeVendor: String, CaseIterable, Codable {
    case fiberhome = "fiberhome"
    case oppo      = "oppo"

    var displayName: String {
        switch self {
        case .fiberhome: return "烽火"
        case .oppo:      return "OPPO"
        }
    }

    var defaultHost: String {
        switch self {
        case .fiberhome: return "192.168.8.1"
        case .oppo:      return "192.168.0.1"
        }
    }

    var defaultUser: String {
        switch self {
        case .fiberhome: return "superadmin"
        case .oppo:      return "admin"
        }
    }

    var hint: String {
        switch self {
        case .fiberhome: return "LG6121F 等烽火 5G CPE"
        case .oppo:      return "OPPO 5G CPE T1 / T2 系列"
        }
    }

    var icon: String {
        switch self {
        case .fiberhome: return "antenna.radiowaves.left.and.right"
        case .oppo:      return "wave.3.right"
        }
    }

    /// 品牌图标资源名（Assets.xcassets）
    var logoAsset: String {
        switch self {
        case .fiberhome: return "BrandFiberHome"
        case .oppo:      return "BrandOPPO"
        }
    }

    /// 数据来源：烽火走原生 API，OPPO 走 WebView 桥接
    var usesWebView: Bool {
        switch self {
        case .fiberhome: return false
        case .oppo:      return true
        }
    }
}

/// 一台设备档案
struct CpeProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var vendor: CpeVendor
    var host: String
    var user: String
    var name: String          // 自定义别名，如「家里」「公司」

    /// 密码单独存 Keychain，用 id 做 key
    var password: String = ""

    var keychainKey: String { "cpe.pass." + id.uuidString }

    var displayTitle: String {
        name.isEmpty ? vendor.displayName : name
    }

    var displaySubtitle: String {
        "\(host) · \(user)"
    }

    static func make(vendor: CpeVendor) -> CpeProfile {
        CpeProfile(vendor: vendor,
                   host: vendor.defaultHost,
                   user: vendor.defaultUser,
                   name: vendor.displayName)
    }
}

/// 多设备档案存储
enum ProfileStore {
    private static let kList = "cpe.profiles"
    private static let kActive = "cpe.activeProfile"

    /// 读取全部档案（密码从 Keychain 补齐）
    static func loadAll() -> [CpeProfile] {
        guard let data = UserDefaults.standard.data(forKey: kList),
              let list = try? JSONDecoder().decode([CpeProfile].self, from: data) else {
            return []
        }
        return list.map { p in
            var copy = p
            copy.password = Keychain.read(p.keychainKey) ?? ""
            return copy
        }
    }

    static func saveAll(_ list: [CpeProfile]) {
        // 密码写 Keychain，JSON 里不带
        for p in list where !p.password.isEmpty {
            Keychain.write(p.keychainKey, p.password)
        }
        let stripped = list.map { p -> CpeProfile in
            var c = p
            c.password = ""
            return c
        }
        if let data = try? JSONEncoder().encode(stripped) {
            UserDefaults.standard.set(data, forKey: kList)
        }
    }

    /// 保存档案：按「厂商 + 地址」去重，同一台设备只保留一条
    static func upsert(_ profile: CpeProfile) {
        var list = loadAll()

        if let i = list.firstIndex(where: { $0.id == profile.id }) {
            list[i] = profile
            saveAll(list)
            return
        }

        // 同厂商 + 同地址 → 视为同一台设备
        if let i = list.firstIndex(where: {
            $0.vendor == profile.vendor && $0.host == profile.host
        }) {
            var updated = profile
            updated.id = list[i].id
            if !list[i].name.isEmpty { updated.name = list[i].name }
            list[i] = updated
            saveAll(list)
            return
        }

        list.append(profile)
        saveAll(list)
    }

    /// 兼容旧调用：等同 upsert
    static func upsertOppo(_ profile: CpeProfile) {
        upsert(profile)
    }

    /// 清理重复档案（同厂商+地址只保留一条）
    static func dedupe() {
        let all = loadAll()
        var list = all
        guard !list.isEmpty else { return }
        var seen: [String: CpeProfile] = [:]
        var result: [CpeProfile] = []
        for p in list {
            let key = p.vendor.rawValue + "|" + p.host
            if let existing = seen[key] {
                // 保留有密码的那条
                if existing.password.isEmpty && !p.password.isEmpty {
                    if let i = result.firstIndex(where: { $0.id == existing.id }) {
                        result[i] = p
                        seen[key] = p
                    }
                }
            } else {
                seen[key] = p
                result.append(p)
            }
        }
        if result.count != list.count {
            saveAll(result)
        }
    }

    static func delete(_ profile: CpeProfile) {
        var list = loadAll()
        list.removeAll { $0.id == profile.id }
        Keychain.delete(profile.keychainKey)
        saveAll(list)
        if activeID == profile.id { activeID = nil }
    }

    /// 当前选中的设备
    static var activeID: UUID? {
        get {
            guard let s = UserDefaults.standard.string(forKey: kActive) else { return nil }
            return UUID(uuidString: s)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: kActive)
        }
    }

    static var active: CpeProfile? {
        guard let id = activeID else { return nil }
        return loadAll().first { $0.id == id }
    }

    /// 兜底：没有档案时，把旧的单设备配置迁移过来
    static func migrateIfNeeded() {
        guard loadAll().isEmpty else { return }
        let old = Settings.load()
        guard !old.password.isEmpty else { return }
        var p = CpeProfile.make(vendor: .fiberhome)
        p.host = old.host
        p.user = old.user
        p.password = old.password
        upsert(p)
        activeID = p.id
    }
}
