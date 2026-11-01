import Foundation

/// 自动识别局域网内的 CPE 厂商
enum CpeDetector {

    /// 可能的网关地址（按常见程度排序）
    static let candidateHosts = [
        "192.168.8.1",      // 烽火 / 华为（靠特征接口区分）
        "192.168.0.1",      // OPPO
        "192.168.1.1",      // 通用
        "192.168.4.1",      // 热点模式
        "192.168.31.1",     // 小米
        "192.168.2.1"
    ]

    struct Result {
        let host: String
        let vendor: CpeVendor
        let evidence: String
    }

    /// 扫描并识别
    static func detect() async -> [Result] {
        var found: [Result] = []
        await withTaskGroup(of: Result?.self) { group in
            for host in candidateHosts {
                group.addTask { await probe(host) }
            }
            for await r in group {
                if let r { found.append(r) }
            }
        }
        return found.sorted {
            (candidateHosts.firstIndex(of: $0.host) ?? 99) <
            (candidateHosts.firstIndex(of: $1.host) ?? 99)
        }
    }

    /// 探测单个地址
    static func probe(_ host: String) async -> Result? {
        guard await isReachable(host) else { return nil }

        // 华为：SesTokInfo 返回 TokInfo
        if let body = await fetch("http://\(host)/api/webserver/SesTokInfo"),
           body.contains("TokInfo") || body.contains("SesInfo") {
            return Result(host: host, vendor: .huawei, evidence: "华为会话接口")
        }

        // OPPO：GetPemKey 返回 RSA 公钥
        if let body = await fetch("http://\(host)/api/webCgi/GetPemKey"), body.contains("pem") {
            return Result(host: host, vendor: .oppo, evidence: "OPPO 公钥接口")
        }

        // 烽火：is_encrypt 接口
        if let body = await fetch("http://\(host)/api/tmp/FHNCAPIS?ajaxmethod=is_encrypt&_=0.1"),
           body.contains("enable") {
            return Result(host: host, vendor: .fiberhome, evidence: "烽火加密接口")
        }

        // 首页特征
        if let html = await fetch("http://\(host)/") {
            let lower = html.lowercased()
            if lower.contains("oppo") {
                return Result(host: host, vendor: .oppo, evidence: "首页标识")
            }
            if lower.contains("fiberhome") || html.contains("烽火") {
                return Result(host: host, vendor: .fiberhome, evidence: "首页标识")
            }
            if lower.contains("huawei") || html.contains("华为") {
                return Result(host: host, vendor: .huawei, evidence: "首页标识")
            }
        }

        return nil
    }

    // MARK: - 底层

    /// 检测某个地址是否可达（供设备切换监听使用）
    static func reachable(_ host: String) async -> Bool {
        await isReachable(host)
    }

    private static func isReachable(_ host: String) async -> Bool {
        await withCheckedContinuation { cont in
            var done = false
            let lock = NSLock()
            let finish: (Bool) -> Void = { v in
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                cont.resume(returning: v)
            }

            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = SOCK_STREAM
                var res: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, "80", &hints, &res) == 0, let info = res else {
                    finish(false); return
                }
                defer { freeaddrinfo(res) }

                let fd = socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else { finish(false); return }
                defer { close(fd) }

                var tv = timeval(tv_sec: 2, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                let ok = connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0
                finish(ok)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(false) }
        }
    }

    private static func fetch(_ urlStr: String) async -> String? {
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
                     forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
