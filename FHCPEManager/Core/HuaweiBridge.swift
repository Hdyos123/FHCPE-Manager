import Foundation
import WebKit
import UIKit
import CommonCrypto

/// 华为 CPE 的 WebView 桥接层
///
/// 华为 H153 的每个请求都要 AES 加密 + RSA 密钥协商。
/// 直接调 HTTP 会返回 100003 / 125002（未加密被拒）。
///
/// 方案：加载设备自己的页面，借用页面里 `$request.$get / $post`
/// （已装好加密拦截器）发请求，把解析好的对象取回来。
@MainActor
final class HuaweiBridge: NSObject, ObservableObject {
    static let shared = HuaweiBridge()

    @Published var ready = false
    @Published var lastError: String?

    private var webView: WKWebView?
    private var host = "192.168.8.1"
    private var user = "admin"
    private var pass = ""
    private var pageLoaded = false

    /// 诊断日志
    private(set) var trace: [String] = []
    private func log(_ s: String) {
        trace.append(s)
        if trace.count > 80 { trace.removeFirst() }
    }

    /// 清空日志（每次新登录前调用）
    func clearTrace() { trace.removeAll() }

    private var callbacks: [String: (Any?) -> Void] = [:]
    private var seq = 0

    private override init() { super.init() }

    // MARK: 原生 SCRAM 登录（照 CPEUltra 的实现）
    //
    // 1. GET  /api/webserver/SesTokInfo → SessionID + Token
    // 2. POST /api/user/challenge_login → salt / iterations / servernonce
    // 3. 计算 clientproof（PBKDF2 + HMAC + XOR）
    // 4. POST /api/user/authentication_login → 建立会话
    // 之后所有请求带 Cookie: SessionID + __RequestVerificationToken

    private var sessionCookie: String = ""
    private var csrfToken: String = ""

    /// 原生 SCRAM 登录，不走 WebView
    func nativeLogin(host: String, user: String, password: String) async -> Bool {
        self.host = host
        self.user = user
        self.pass = password
        sessionCookie = ""
        csrfToken = ""

        let base = "http://\(host)"
        log("SCRAM 登录开始 \(user)@\(host)")

        // ① 取会话
        guard await fetchSession(base) else {
            lastError = "无法获取会话"
            return false
        }
        log("会话建立")

        // ② 挑战
        let firstNonce = Self.randomHex(32)
        let chBody = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><request><username>"
            + Self.esc(user) + "</username><firstnonce>"
            + firstNonce + "</firstnonce><mode>1</mode></request>"

        guard let ch = await post(base, "/api/user/challenge_login", chBody) else {
            lastError = "挑战请求失败"
            return false
        }
        guard let salt = Self.tag(ch, "salt"),
              let iterStr = Self.tag(ch, "iterations"),
              let serverNonce = Self.tag(ch, "servernonce") else {
            lastError = "挑战响应异常：" + String(ch.prefix(80))
            return false
        }
        let iterations = Int(iterStr) ?? 1000
        log("挑战 OK salt=\(salt.count/2)B iter=\(iterations)")

        // ③ 计算证明
        // forge 的 pbkdf2 把 salt 当 binary string → utf8 编码
        guard let saltBytes = Self.hexToBytes(salt) else {
            lastError = "salt 解析失败"
            return false
        }
        // 模拟 forge：binary string → utf8
        let saltForPbkdf2 = String(bytes: saltBytes, encoding: .isoLatin1)?.data(using: .utf8)
            ?? Data(saltBytes)

        guard let pwdBytes = password.data(using: .utf8) else {
            lastError = "密码编码失败"
            return false
        }

        guard let salted = Self.pbkdf2(pwdBytes, salt: saltForPbkdf2, iterations: iterations) else {
            lastError = "PBKDF2 失败"
            return false
        }

        let clientKey = Self.hmac(salted, "Client Key")
        let storedKey = Self.sha256(clientKey)
        let authMsg = firstNonce + "," + serverNonce + "," + serverNonce
        let clientSig = Self.hmac(storedKey, authMsg)

        guard let ck = Self.hexToBytes(clientKey),
              let cs = Self.hexToBytes(clientSig) else {
            lastError = "证明计算失败"
            return false
        }
        let proof = Self.xorHex(ck, cs)

        // ④ 认证
        let authBody = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><request><clientproof>"
            + proof + "</clientproof><finalnonce>"
            + serverNonce + "</finalnonce><logintype>1</logintype></request>"

        guard let au = await post(base, "/api/user/authentication_login", authBody) else {
            lastError = "认证请求失败"
            return false
        }
        if au.contains("<error>") {
            let code = Self.tag(au, "code") ?? "?"
            let wait = Self.tag(au, "waittime") ?? ""
            let remain = Self.tag(au, "remaincount") ?? ""
            lastError = "认证失败 code=\(code)"
                + (wait.isEmpty ? "" : " 等待\(wait)秒")
                + (remain.isEmpty ? "" : " 剩余\(remain)次")
            log("认证失败 \(au.prefix(150))")
            return false
        }
        log("认证 OK")

        // ⑤ 刷新会话
        _ = await fetchSession(base)

        // ⑥ 验证
        if let st = await get(base, "/api/monitoring/status"), st.contains("<response>") {
            log("✓ SCRAM 登录成功")
            loggedInNative = true
            return true
        }
        lastError = "登录后仍无法读取数据"
        return false
    }

    private(set) var loggedInNative = false

    // MARK: 原生 HTTP

    private func fetchSession(_ base: String) async -> Bool {
        guard let r = await rawGet(base, "/api/webserver/SesTokInfo"),
              let tk = Self.tag(r.body, "TokInfo") else { return false }
        csrfToken = Self.unesc(tk)
        for (k, v) in r.cookies { sessionCookie = "\(k)=\(v)" }
        return true
    }

    private struct RawResp { let body: String; let cookies: [(String, String)] }

    private func rawGet(_ base: String, _ path: String) async -> RawResp? {
        guard var comps = URLComponents(string: base + path) else { return nil }
        comps.queryItems = [URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 8
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        req.setValue("http://\(host)/", forHTTPHeaderField: "Referer")
        if !sessionCookie.isEmpty {
            req.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            return RawResp(body: String(data: d, encoding: .utf8) ?? "",
                           cookies: Self.parseCookies(resp))
        } catch { return nil }
    }

    private func post(_ base: String, _ path: String, _ body: String) async -> String? {
        guard var comps = URLComponents(string: base + path) else { return nil }
        comps.queryItems = [URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        req.timeoutInterval = 10
        req.setValue("application/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        req.setValue("http://\(host)/", forHTTPHeaderField: "Referer")
        req.setValue(csrfToken, forHTTPHeaderField: "__RequestVerificationToken")
        if !sessionCookie.isEmpty {
            req.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            for (k, v) in Self.parseCookies(resp) { sessionCookie = "\(k)=\(v)" }
            return String(data: d, encoding: .utf8) ?? ""
        } catch { return nil }
    }

    private func get(_ base: String, _ path: String) async -> String? {
        await rawGet(base, path)?.body
    }

    private static func parseCookies(_ resp: URLResponse) -> [(String, String)] {
        guard let h = resp as? HTTPURLResponse else { return [] }
        var out: [(String, String)] = []
        for (k, v) in h.allHeaderFields {
            guard String(describing: k).lowercased() == "set-cookie" else { continue }
            let raw = String(describing: v)
            for part in raw.components(separatedBy: ",") {
                let kv = part.components(separatedBy: ";").first ?? ""
                let pair = kv.components(separatedBy: "=")
                if pair.count >= 2 {
                    let name = pair[0].trimmingCharacters(in: .whitespaces)
                    let val = pair.dropFirst().joined(separator: "=")
                        .trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { out.append((name, val)) }
                }
            }
        }
        return out
    }

    // MARK: 加密工具

    static func unesc(_ s: String) -> String {
        s.replacingOccurrences(of: "&#x2F;", with: "/")
         .replacingOccurrences(of: "&#47;", with: "/")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func tag(_ xml: String, _ name: String) -> String? {
        guard let a = xml.range(of: "<\(name)>"),
              let b = xml.range(of: "</\(name)>") else { return nil }
        let v = String(xml[a.upperBound..<b.lowerBound])
        return v.isEmpty ? nil : v
    }

    static func randomHex(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hexToBytes(_ s: String) -> Data? {
        var d = Data()
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
            guard let b = UInt8(s[idx..<next], radix: 16) else { return nil }
            d.append(b)
            idx = next
        }
        return d
    }

    static func pbkdf2(_ pwd: Data, salt: Data, iterations: Int) -> String? {
        var out = [UInt8](repeating: 0, count: 32)
        let st = pwd.withUnsafeBytes { p in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     p.bindMemory(to: Int8.self).baseAddress, pwd.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                     UInt32(iterations),
                                     &out, out.count)
            }
        }
        guard st == kCCSuccess else { return nil }
        return Data(out).map { String(format: "%02x", $0) }.joined()
    }

    static func hmac(_ hexKey: String, _ msg: String) -> String {
        guard let key = hexToBytes(hexKey) else { return "" }
        var out = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        let msgData = msg.data(using: .utf8) ?? Data()
        key.withUnsafeBytes { k in
            msgData.withUnsafeBytes { m in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       k.baseAddress, key.count,
                       m.baseAddress, msgData.count,
                       &out)
            }
        }
        return Data(out).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ hex: String) -> String {
        guard let d = hexToBytes(hex) else { return "" }
        var out = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        d.withUnsafeBytes { p in
            _ = CC_SHA256(p.baseAddress, CC_LONG(d.count), &out)
        }
        return Data(out).map { String(format: "%02x", $0) }.joined()
    }

    static func xorHex(_ a: Data, _ b: Data) -> String {
        let n = min(a.count, b.count)
        var out = Data(count: n)
        for i in 0..<n { out[i] = a[i] ^ b[i] }
        return out.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 挂载

    func attach(to view: UIView) {
        guard webView == nil else { return }

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true

        let ucc = WKUserContentController()
        ucc.add(self, name: "huaweiBridge")
        cfg.userContentController = ucc

        let bootstrap = """
        (function(){
          window.__hwCall = function(id, fnBody) {
            var finish = function(p){ try {
              window.webkit.messageHandlers.huaweiBridge.postMessage(
                JSON.stringify({id:id, payload:p})); } catch(e){} };
            try {
              var r = (new Function('return (' + fnBody + ')'))();
              if (r && typeof r.then === 'function') {
                r.then(function(v){ finish({ok:true, data:v}); })
                 .catch(function(e){ finish({ok:false, err:String(e)}); });
              } else { finish({ok:true, data:r}); }
            } catch(e) { finish({ok:false, err:String(e)}); }
          };
        })();
        """
        ucc.addUserScript(WKUserScript(source: bootstrap,
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: false))

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        // 不能为 0，否则 WebKit 暂停 JS 执行
        wv.alpha = 0.01
        wv.isUserInteractionEnabled = false
        view.addSubview(wv)
        wv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // 尺寸不能太小：Element Plus 按钮点击依赖布局计算
            wv.widthAnchor.constraint(equalToConstant: 200),
            wv.heightAnchor.constraint(equalToConstant: 200),
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        ])
        webView = wv
        log("WebView 已创建")
    }

    // MARK: 登录

    func login(host: String, user: String, password: String) async -> Bool {
        self.host = host
        self.user = user
        self.pass = password
        ready = false
        pageLoaded = false
        trace.removeAll()
        log("开始加载 \(host)")

        guard let wv = webView else {
            lastError = "WebView 未挂载（HuaweiHost 没加进视图）"
            log("✗ WebView 未初始化 — 检查 FHCPEManagerApp 里有没有 HuaweiHost()")
            return false
        }
        log("WebView 已就绪")

        guard let url = URL(string: "http://\(host)/") else {
            lastError = "地址无效"
            return false
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData
        wv.load(req)

        var waited = 0.0
        while !pageLoaded && waited < 15 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            waited += 0.2
        }
        log(pageLoaded ? "① 页面加载完成 \(Int(waited))s" : "① ✗ 页面加载超时 25s")

        // 页面加载后检查桥接函数是否注入成功
        let bridgeType = (await evalSync("typeof window.__hwCall")) as? String
        log("① 桥接函数: " + (bridgeType ?? "nil"))
        let docReady = (await evalSync("document.readyState")) as? String
        log("① 文档状态: " + (docReady ?? "nil"))

        // 等 Vue 渲染出登录框
        var ok = false
        for i in 0..<24 {
            // 用同步求值探测（更可靠，不依赖注入）
            let inputsRaw = await evalSync("document.querySelectorAll('input').length")
            let hashRaw = await evalSync("location.hash")
            let inputs = (inputsRaw as? Int) ?? ((inputsRaw as? NSNumber)?.intValue ?? -1)
            let hashNow = (hashRaw as? String) ?? "?"
            // 华为只需要密码框（1 个）+ 可选的语言下拉
            var hasPwd = false
            if let raw = await evalSync("!!document.querySelector('input[type=password]')") {
                hasPwd = (raw as? Bool) ?? ((raw as? NSNumber)?.boolValue ?? false)
            }
            if hasPwd && inputs >= 1 {
                ok = true
                log("② 登录框就绪 \(i/2)s · hash=\(hashNow) · inputs=\(inputs)")
                break
            }
            if i % 10 == 0 {
                log("  等待登录框 \(i/2)s · inputs=\(inputs) · hash=\(hashNow)")
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        guard ok else {
            lastError = "页面未渲染登录框（20 秒超时）"
            log("② ✗ 20 秒内未找到登录框")
            return false
        }

        // 如果已经在登录后页面，跳过登录
        if await isLoggedIn() {
            ready = true
            log("② 已有会话，跳过登录")
            return true
        }

        return await doLogin()
    }

    /// 判断页面是否已登录
    ///
    /// 注意：$request 在登录页也存在，不能作为判据。
    /// 正确标准：hash 不是 login，且输入框 ≤ 1 个。
    private func isLoggedIn() async -> Bool {
        // 用 evalSync，不依赖注入
        let hashV = (await evalSync("location.hash")) as? String ?? ""
        let h = hashV.lowercased()

        // hash 为空说明页面正在重载，不算完成
        if h.isEmpty { return false }
        if h.contains("login") { return false }

        // 必须已经进入 home 页
        if !h.contains("home") { return false }

        // 密码框不应再存在（登录后表单已销毁）
        let hasPwdRaw = await evalSync("!!document.querySelector('input[type=password]')")
        let hasPwd = (hasPwdRaw as? Bool) ?? ((hasPwdRaw as? NSNumber)?.boolValue ?? false)
        if hasPwd { return false }

        return true
    }

    private func doLogin() async -> Bool {
        // 注意：这里不再包 function(){}，而是直接执行 IIFE，
        // 避免 __hwCall 里的 new Function 二次包装导致 this/闭包异常
        let body = """
        (function(){
          return new Promise(function(resolve){
            try {
              // 华为登录页没有账号输入框，只有密码框（type=password）
              // 第一个 input 是语言选择器，不能往里塞文本，否则按钮点击无效
              var pwd = document.querySelector('input[type=password]');
              if (!pwd) { resolve('NO_PASSWORD'); return; }
              var setter = Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'value').set;
              setter.call(pwd, '\(jsEscape(pass))');
              pwd.dispatchEvent(new Event('input', {bubbles:true}));
              pwd.dispatchEvent(new Event('change', {bubbles:true}));
              window.__fillCheck = 'len=' + pwd.value.length + ' vis=' + (pwd.offsetParent !== null);

              setTimeout(function(){
                var btn = Array.prototype.slice.call(
                  document.querySelectorAll('button')).filter(function(b){
                    var t = (b.textContent || '').trim();
                    return t === '登录' || /^login$/i.test(t);
                  })[0];
                if (btn) {
                  window.__btnCheck = 'disabled=' + btn.disabled
                    + ' text=' + (btn.textContent||'').trim();
                  // 关键：用完整鼠标事件序列触发。
                  // 直接 .click() 在 WKWebView 小尺寸视图里可能不生效
                  try {
                    btn.focus();
                    btn.dispatchEvent(new MouseEvent('mousedown', {bubbles:true, cancelable:true, view:window}));
                    btn.dispatchEvent(new MouseEvent('mouseup',   {bubbles:true, cancelable:true, view:window}));
                    btn.dispatchEvent(new MouseEvent('click',     {bubbles:true, cancelable:true, view:window}));
                    btn.click();
                  } catch(e) {
                    btn.click();
                  }
                  // 登录成功后页面会重载，等 4 秒
                  setTimeout(function(){ resolve(location.hash); }, 4000);
                } else {
                  resolve('NO_BUTTON');
                }
              }, 400);
            } catch(e) { resolve('ERR:' + e.message); }
          });
        })()
        """
        let r = await jsCall(body, timeout: 18)
        let hash = (r as? String) ?? ""
        log("③ 点击登录后 hash=\(hash.isEmpty ? "(空)" : hash)")

        // 填表 / 按钮 状态
        let fc = (await evalSync("window.__fillCheck || '无'")) as? String
        let bc = (await evalSync("window.__btnCheck || '无'")) as? String
        log("③ 填表: " + (fc ?? "?"))
        log("③ 按钮: " + (bc ?? "?"))

        // 记录页面完整状态，便于诊断
        let st = (await evalSync("JSON.stringify({h:location.hash,n:document.querySelectorAll('input').length,url:location.href})")) as? String
        log("③ 页面状态: " + (st ?? "nil"))

        if hash.hasPrefix("ERR") {
            lastError = "页面异常：\(hash)"
            return false
        }
        if hash == "NO_INPUT" {
            lastError = "页面未渲染登录框"
            return false
        }

        // 等页面跳转完成
        var lastProbe = ""
        var lastHash = ""
        for i in 0..<20 {
            let h = (await evalSync("location.hash")) as? String ?? ""
            let n = (await evalSync("document.querySelectorAll('input').length")) as? Int ?? -1
            lastHash = h

            if i % 4 == 0 || h.contains("home") {
                log("④ \(i/2)s · hash=\(h.isEmpty ? "(空)" : h) · inputs=\(n)")
            }

            // 页面重载中：hash 为空或仍在 login 页
            if h.isEmpty || h.lowercased().contains("login") {
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            // 已进 home 页
            if h.lowercased().contains("home") && n <= 1 {
                if i == 0 { try? await Task.sleep(nanoseconds: 1_000_000_000) }

                // 探针1：$request 是否存在
                let hasReq = (await evalSync(
                    "!!(document.querySelector('#app') && document.querySelector('#app').__vue_app__ && document.querySelector('#app').__vue_app__.config.globalProperties.$request)") as? Bool) ?? false
                if !hasReq {
                    lastProbe = "无$request"
                    if i % 4 == 0 { log("④ 探针: \(lastProbe)") }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }

                // 探针2：真的取一次数据
                let probe = await get("monitoringStatus")
                if let err = probe["__err"] as? String {
                    lastProbe = "code=" + err
                    log("④ 探针失败 \(lastProbe)")
                } else if probe.isEmpty {
                    lastProbe = "空数据"
                    log("④ 探针返回空")
                } else {
                    ready = true
                    // 保存会话，下次免登录
                    if !sessionCookie.isEmpty {
                        SessionStore.save(sessionCookie, host: host, vendor: "huawei")
                    }
                    log("④ 探针通过 (\(probe.count) 项) · ✓ 登录成功")
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        lastError = "登录失败：最终 hash=\(lastHash.isEmpty ? "(空)" : lastHash)"
            + (lastProbe.isEmpty ? "" : " 探针=\(lastProbe)")
        log("④ ✗ 登录未完成 · 最终 hash=\(lastHash) · 探针=\(lastProbe)")
        return false
    }

    // MARK: 调用设备 API

    /// GET 请求（用页面内部别名，如 hostList / singal / monitoringStatus）
    func get(_ alias: String) async -> [String: Any] {
        // 用 evalAsync 直接等 Promise，不依赖 __hwCall
        let js = """
        (function(){
          var app = document.querySelector('#app');
          var gp = app && app.__vue_app__ && app.__vue_app__.config.globalProperties;
          var R = gp && gp.$request;
          if (!R) { return JSON.stringify({__err:'NO_REQUEST'}); }
          return R.$get('\(jsEscape(alias))', {}).then(function(r){
            if (r && r.error) { return JSON.stringify({__err:String(r.error.code||'?')}); }
            var o = r && r.response !== undefined ? r.response : r;
            return JSON.stringify(o || {});
          }).catch(function(e){
            return JSON.stringify({__err:String(e && e.message)});
          });
        })()
        """
        // WKWebView 不支持直接等 Promise，改为：启动后存全局变量，轮询读取
        let tok = "\(alias)_\(Int(Date().timeIntervalSince1970 * 1000))"
        let kick = """
        (function(){
          try {
            var app = document.querySelector('#app');
            var gp = app && app.__vue_app__ && app.__vue_app__.config.globalProperties;
            var R = gp && gp.$request;
            window.__hwRes = window.__hwRes || {};
            if (!R) { window.__hwRes['\(tok)'] = JSON.stringify({__err:'NO_REQUEST'}); return 'kicked'; }
            R.$get('\(jsEscape(alias))', {}).then(function(r){
              var out;
              if (r && r.error) out = {__err: String(r.error.code||'?')};
              else {
                var o = r && r.response !== undefined ? r.response : r;
                out = o || {};
              }
              window.__hwRes['\(tok)'] = JSON.stringify(out);
            }).catch(function(e){
              window.__hwRes['\(tok)'] = JSON.stringify({__err:String(e && e.message)});
            });
            return 'kicked';
          } catch(e) {
            window.__hwRes['\(tok)'] = JSON.stringify({__err:'EXC:'+e.message});
            return 'exc';
          }
        })()
        """
        _ = await evalSync(kick, timeout: 3)

        // 轮询：0.15 秒一次，最多 3 秒
        var s: String? = nil
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let r = await evalSync("window.__hwRes && window.__hwRes['\(tok)'] || ''") as? String,
               !r.isEmpty {
                s = r
                break
            }
        }
        guard let s else {
            log("   \(alias) → 轮询超时")
            return ["__err": "timeout"]
        }
        guard let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            log("   \(alias) → 解析失败: \(s.prefix(60))")
            return ["__err": "parse"]
        }
        if let e = o["__err"] as? String {
            log("   接口 \(alias) → \(e)")
            return ["__err": e]
        }
        if let e = o["error"] as? [String: Any] {
            let c = e["code"] ?? "?"
            log("   接口 \(alias) → error \(c)")
            return ["__err": "\(c)"]
        }
        return o
    }

    /// POST 请求
    func post(_ alias: String, _ body: [String: Any]) async -> [String: Any] {
        let bd = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        let bs = String(data: bd, encoding: .utf8) ?? "{}"

        // 同 get：启动后存全局，轮询读取
        let tok = "\(alias)_\(Int(Date().timeIntervalSince1970 * 1000))"
        let kick = """
        (function(){
          try {
            var app = document.querySelector('#app');
            var gp = app && app.__vue_app__ && app.__vue_app__.config.globalProperties;
            var R = gp && gp.$request;
            window.__hwRes = window.__hwRes || {};
            if (!R) { window.__hwRes['\(tok)'] = JSON.stringify({__err:'NO_REQUEST'}); return 'kicked'; }
            R.$post('\(jsEscape(alias))', \(bs)).then(function(r){
              var out;
              if (r && r.error) out = {__err: String(r.error.code||'?')};
              else {
                var o = r && r.response !== undefined ? r.response : r;
                out = o || {};
              }
              window.__hwRes['\(tok)'] = JSON.stringify(out);
            }).catch(function(e){
              window.__hwRes['\(tok)'] = JSON.stringify({__err:String(e && e.message)});
            });
            return 'kicked';
          } catch(e) {
            window.__hwRes['\(tok)'] = JSON.stringify({__err:'EXC:'+e.message});
            return 'exc';
          }
        })()
        """
        _ = await evalSync(kick, timeout: 3)

        var s: String? = nil
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let r = await evalSync("window.__hwRes && window.__hwRes['\(tok)'] || ''") as? String,
               !r.isEmpty {
                s = r
                break
            }
        }
        guard let s,
              let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            log("   \(alias) POST → 轮询超时")
            return ["__err": "timeout"]
        }
        if let e = o["__err"] as? String { return ["__err": e] }
        return o
    }

    /// 返回列表（hostList 等是数组）
    func getList(_ alias: String) async -> [[String: Any]] {
        let js = """
        function(){
          return new Promise(function(resolve){
            try {
              var app = document.querySelector('#app');
              var gp = app && app.__vue_app__ && app.__vue_app__.config.globalProperties;
              var R = gp && gp.$request;
              if (!R) { resolve('{"__err":"NO_REQUEST"}'); return; }
              R.$get('\(jsEscape(alias))', {}).then(function(r){
                if (r && r.error) { resolve('{"__err":"' + (r.error.code||'?') + '"}'); return; }
                var o = r && r.response !== undefined ? r.response : r;
                if (Array.isArray(o)) { resolve(JSON.stringify({__list:o})); return; }
                // 对象里可能嵌套列表
                resolve(JSON.stringify({__obj:o}));
              }).catch(function(e){ resolve('{"__err":"' + String(e&&e.message) + '"}'); });
            } catch(e) { resolve('{"__err":"EXC"}'); }
          });
        }
        """
        guard let s = await jsCall(js, timeout: 12) as? String,
              let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return []
        }
        if let list = o["__list"] as? [[String: Any]] { return list }
        if let obj = o["__obj"] as? [String: Any] {
            // 把键值对按数字键排序转成数组
            let keys = obj.keys.compactMap { Int($0) }.sorted()
            if !keys.isEmpty {
                return keys.compactMap { k -> [String: Any]? in
                    var item = obj[String(k)] as? [String: Any]
                    item?["__idx"] = k
                    return item
                }
            }
        }
        return []
    }

    // MARK: 底层

    private func jsCall(_ fn: String, timeout: TimeInterval = 10) async -> Any? {
        guard let wv = webView else { return nil }
        seq += 1
        let cid = "h\(seq)"

        return await withCheckedContinuation { (cont: CheckedContinuation<Any?, Never>) in
            var finished = false
            let lock = NSLock()
            let finish: (Any?) -> Void = { v in
                lock.lock(); defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                cont.resume(returning: v)
            }

            callbacks[cid] = { v in finish(v) }
            let wrapped = "window.__hwCall(\(quote(cid)), \(quote(fn)));"
            wv.evaluateJavaScript(wrapped) { _, err in
                if err != nil {
                    Task { @MainActor in
                        if let cb = self.callbacks.removeValue(forKey: cid) { cb(nil) }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                if let cb = self?.callbacks.removeValue(forKey: cid) { cb(nil) }
            }
        }
    }



    /// 直接执行 JS 并等待 Promise（不依赖 __hwCall 注入）
    /// 用于登录后页面重载、注入脚本失效的场景
    private func evalAsync(_ js: String, timeout: TimeInterval = 12) async -> Any? {
        guard let wv = webView else { return nil }

        let work = Task { @MainActor () -> Any? in
            await withCheckedContinuation { (cont: CheckedContinuation<Any?, Never>) in
                wv.evaluateJavaScript(js) { res, err in
                    if let e = err {
                        Task { @MainActor in self.log("evalAsync 错误: \(e.localizedDescription)") }
                    }
                    cont.resume(returning: res)
                }
            }
        }

        let timer = Task { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) }

        return await withTaskGroup(of: AnyBox?.self) { group in
            group.addTask { AnyBox(await work.value) }
            group.addTask { _ = await timer.value; return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            work.cancel()
            timer.cancel()
            return first?.value
        }
    }

    /// 直接求值（不依赖注入的 __hwCall）
    /// 用 withThrowingTaskGroup 做超时竞速，避免主线程被 asyncAfter 卡住
    private func evalSync(_ js: String, timeout: TimeInterval = 5) async -> Any? {
        guard let wv = webView else { return nil }

        let work = Task { @MainActor () -> Any? in
            await withCheckedContinuation { (cont: CheckedContinuation<Any?, Never>) in
                wv.evaluateJavaScript(js) { res, err in
                    if let e = err {
                        Task { @MainActor in self.log("eval 错误: \(e.localizedDescription)") }
                    }
                    cont.resume(returning: res)
                }
            }
        }

        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        }

        return await withTaskGroup(of: AnyBox?.self) { group in
            group.addTask { AnyBox(await work.value) }
            group.addTask { _ = await timer.value; return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            work.cancel()
            timer.cancel()
            return first?.value
        }
    }

    private func quote(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let arr = String(data: d, encoding: .utf8) ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())
    }

    private func jsEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "'", with: "\\'")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "")
    }
}

/// 把任意值装箱，供 TaskGroup 使用
private struct AnyBox: @unchecked Sendable {
    let value: Any?
    init(_ v: Any?) { value = v }
}

// MARK: - 回调

extension HuaweiBridge: WKScriptMessageHandler {
    nonisolated func userContentController(_ ucc: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let s = message.body as? String,
              let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let cid = o["id"] as? String else { return }
        let payload = o["payload"] as? [String: Any] ?? [:]
        let ok = payload["ok"] as? Bool ?? false
        let value: Any? = ok ? payload["data"] : nil

        Task { @MainActor in
            if let cb = self.callbacks.removeValue(forKey: cid) { cb(value) }
        }
    }
}

// MARK: - 导航

extension HuaweiBridge: WKNavigationDelegate {
    nonisolated func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        Task { @MainActor in
            self.pageLoaded = true
            self.log("didFinish: \(wv.url?.absoluteString ?? "?")")
        }
    }

    nonisolated func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError e: Error) {
        Task { @MainActor in self.log("✗ 加载失败: \(e.localizedDescription)") }
    }
    nonisolated func webView(_ wv: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError e: Error) {
        Task { @MainActor in self.log("✗ 加载失败: \(e.localizedDescription)") }
    }

    /// 按真实路径 GET（页面内部会加密）
    func getPath(_ path: String) async -> [String: Any] {
        await callRequest("get", path, nil)
    }

    /// 按真实路径 POST
    func postPath(_ path: String, _ body: [String: Any]) async -> [String: Any] {
        await callRequest("post", path, body)
    }

    /// 统一的请求执行
    private func callRequest(_ method: String, _ path: String, _ body: [String: Any]?) async -> [String: Any] {
        guard ready else { return ["__err": "not_ready"] }

        var bodyJSON = "null"
        if let b = body,
           let d = try? JSONSerialization.data(withJSONObject: b),
           let str = String(data: d, encoding: .utf8) {
            bodyJSON = str
        }

        let js = """
        function(){
          return new Promise(function(resolve){
            try {
              var R = document.querySelector('#app').__vue_app__.config.globalProperties.$request;
              var p = (R.%METHOD%('%(PATH%)', %BODY%));
              p.then(function(r){
                var out = (r && r.response !== undefined) ? r.response : r;
                resolve(JSON.stringify(out));
              }).catch(function(e){
                resolve(JSON.stringify({__err: String(e && e.message || e)}));
              });
            } catch(e) {
              resolve(JSON.stringify({__err: String(e && e.message || e)}));
            }
          });
        }
        """
        .replacingOccurrences(of: "%METHOD%", with: method)
        .replacingOccurrences(of: "%PATH%", with: path)
        .replacingOccurrences(of: "%BODY%", with: bodyJSON)

        let res = await jsCall(js)
        guard let str = res as? String,
              let d = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return ["__err": "parse"]
        }
        return obj
    }

    // MARK: 原生取数（SCRAM 登录后可用）

    /// 按路径 GET，返回解析后的字典
    func nativeGetPath(_ path: String) async -> [String: Any] {
        guard loggedInNative else { return [:] }
        let base = "http://\(host)"
        guard let body = await get(base, path) else { return [:] }
        if body.contains("<error>") {
            let code = Self.tag(body, "code") ?? "?"
            return ["__err": code]
        }
        return Self.xmlToDict(body)
    }

    /// 极简 XML → 字典
    static func xmlToDict(_ xml: String) -> [String: Any] {
        var out: [String: Any] = [:]
        // 去掉声明
        var body = xml
        if let r = body.range(of: "?>") { body = String(body[r.upperBound...]) }

        // 提取最外层单层元素：<a>v</a>
        let pattern = "<([A-Za-z0-9_]+)>([^<]*)</\\1>"
        if let re = try? NSRegularExpression(pattern: pattern) {
            let ns = body as NSString
            for m in re.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
                guard m.numberOfRanges >= 3 else { continue }
                let k = ns.substring(with: m.range(at: 1))
                let v = ns.substring(with: m.range(at: 2))
                out[k] = v
            }
        }
        return out
    }

    /// 批量并发取数：一次 JS 调用把所有接口都发出去，再一起等
    func getBatch(_ aliases: [String]) async -> [String: [String: Any]] {
        let tok = "batch_\(Int(Date().timeIntervalSince1970 * 1000))"
        let aliasJSON = (try? JSONSerialization.data(withJSONObject: aliases))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        let kick = """
        (function(){
          try {
            var app = document.querySelector('#app');
            var gp = app && app.__vue_app__ && app.__vue_app__.config.globalProperties;
            var R = gp && gp.$request;
            window.__hwRes = window.__hwRes || {};
            if (!R) { window.__hwRes['\(tok)'] = JSON.stringify({}); return 'none'; }
            var list = \(aliasJSON);
            var done = 0, out = {};
            window.__hwRes['\(tok)'] = '';
            list.forEach(function(a){
              R.$get(a, {}).then(function(r){
                var v;
                if (r && r.error) v = {__err: String(r.error.code||'?')};
                else v = (r && r.response !== undefined ? r.response : r) || {};
                out[a] = v;
              }).catch(function(e){
                out[a] = {__err: String(e && e.message)};
              }).then(function(){
                done++;
                if (done === list.length) {
                  window.__hwRes['\(tok)'] = JSON.stringify(out);
                }
              });
            });
            return 'kicked';
          } catch(e) {
            window.__hwRes['\(tok)'] = JSON.stringify({});
            return 'exc';
          }
        })()
        """
        _ = await evalSync(kick, timeout: 3)

        var raw: String? = nil
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let r = await evalSync("window.__hwRes && window.__hwRes['\(tok)'] || ''") as? String,
               !r.isEmpty {
                raw = r
                break
            }
        }
        guard let raw,
              let d = raw.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            log("   batch 超时或解析失败")
            return [:]
        }
        var result: [String: [String: Any]] = [:]
        for (k, v) in o {
            if let item = v as? [String: Any] { result[k] = item }
        }
        return result
    }

    /// 用保存的会话尝试免登录
    /// 返回 true 表示会话仍有效
    func tryRestoreSession(host: String) async -> Bool {
        guard let saved = SessionStore.load(vendor: "huawei", host: host) else {
            return false
        }
        self.host = host
        sessionCookie = saved
        loggedInNative = false
        trace.removeAll()
        log("尝试复用会话…")

        // 先拿新 token（沿用旧 cookie）
        guard let url = URL(string: "http://\(host)/api/webserver/SesTokInfo") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        req.setValue("Cookie", saved)
        guard let (d, _) = try? await URLSession.shared.data(for: req),
              let body = String(data: d, encoding: .utf8),
              let tk = Self.tag(body, "TokInfo") else {
            log("  会话探测失败（无响应）")
            SessionStore.clear(vendor: "huawei")
            return false
        }
        csrfToken = Self.unesc(tk)

        // 用这个 token 探一次数据
        let probe = await get("monitoringStatus")
        if probe["__err"] != nil || probe.isEmpty {
            log("  会话已失效")
            SessionStore.clear(vendor: "huawei")
            return false
        }

        ready = true
        log("✓ 会话有效，免登录成功")
        return true
    }
}
