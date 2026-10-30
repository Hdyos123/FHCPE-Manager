import Foundation
import UIKit
import WebKit
import Combine

/// 用隐藏的 WKWebView 承载 CPE 会话。
///
/// 重要：`evaluateJavaScript` **不会等待 Promise**，
/// 直接返回 Promise 对象（序列化为空）。所以这里用
/// `WKScriptMessageHandler` 做异步回调桥。
@MainActor
final class CpeBridge: NSObject, ObservableObject {
    static let shared = CpeBridge()

    @Published var ready = false
    @Published var lastError: String?
    @Published var diagInfo: String?

    private var webView: WKWebView?
    private var host: String = "192.168.8.1"
    private weak var container: UIView?
    private var pendingLogin: CheckedContinuation<Bool, Never>?
    private var pageLoaded = false

    /// 异步回调：callId -> 结果
    private var callbacks: [String: (Any?) -> Void] = [:]
    private var cbSeq = 0

    private var loginCreds: (String, String)?

    private override init() { super.init() }

    // MARK: - UA

    static var safariUA: String {
        let v = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        let major = UIDevice.current.systemVersion.split(separator: ".").first ?? "16"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(v) like Mac OS X) "
             + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
             + "Version/\(major).0 Mobile/15E148 Safari/604.1"
    }

    // MARK: - 初始化

    func attach(to view: UIView) {
        container = view
        guard webView == nil else { return }

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true

        // 回调通道
        let ucc = WKUserContentController()
        ucc.add(self, name: "cpeBridge")
        cfg.userContentController = ucc

        // 注入 Promise 包装器 + UA 覆盖
        let bootstrap = """
        (function(){
          // 覆盖 UA，部分固件读 navigator.userAgent
          try {
            Object.defineProperty(navigator, 'userAgent', {
              get: function(){ return '\(Self.safariUA)'; }
            });
          } catch(e) {}

          // 统一的异步桥：把 Promise 结果推回原生
          window.__cpeCall = function(id, fnBody) {
            var finish = function(payload){
              try {
                window.webkit.messageHandlers.cpeBridge.postMessage(
                  JSON.stringify({id: id, payload: payload}));
              } catch(e) {}
            };
            try {
              var p = (new Function('return (' + fnBody + ')'))();
              if (p && typeof p.then === 'function') {
                p.then(function(v){ finish({ok:true, data:v}); })
                 .catch(function(e){ finish({ok:false, err:String(e)}); });
              } else {
                finish({ok:true, data:p});
              }
            } catch(e) {
              finish({ok:false, err:String(e)});
            }
          };
        })();
        """
        ucc.addUserScript(WKUserScript(source: bootstrap,
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: false))

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.customUserAgent = Self.safariUA
        wv.navigationDelegate = self
        wv.alpha = 0.01
        wv.isUserInteractionEnabled = false
        view.addSubview(wv)
        wv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wv.widthAnchor.constraint(equalToConstant: 1),
            wv.heightAnchor.constraint(equalToConstant: 1),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.topAnchor.constraint(equalTo: view.topAnchor)
        ])
        webView = wv
    }

    // MARK: - 登录

    func login(host: String, user: String, password: String) async -> Bool {
        self.host = host
        guard let wv = webView else {
            lastError = "WebView 未初始化"
            return false
        }
        let base = host.hasPrefix("http") ? host : "http://\(host)"
        guard let url = URL(string: base + "/login.html") else {
            lastError = "地址格式不正确"
            return false
        }

        ready = false
        pageLoaded = false
        loginCreds = (user, password)

        return await withCheckedContinuation { cont in
            self.pendingLogin = cont
            var req = URLRequest(url: url)
            req.setValue(Self.safariUA, forHTTPHeaderField: "User-Agent")
            req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
            req.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 15
            wv.load(req)

            // 超时保护
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard let self, let p = self.pendingLogin else { return }
                self.pendingLogin = nil
                self.lastError = "连接超时，请检查是否连着 CPE 的 Wi-Fi"
                p.resume(returning: false)
            }
        }
    }

    private func doJSLogin() async -> Bool {
        guard let (user, password) = loginCreds else { return false }

        // 诊断：等待 $post 出现，最多重试 6 次（共约 3 秒）
        var hasPost = false
        for attempt in 0..<6 {
            let probe = await jsCall("""
            function(){
              return JSON.stringify({
                post: typeof $post,
                multipost: typeof $multipost,
                axios: typeof axios,
                url: location.href,
                ready: document.readyState,
                scripts: document.scripts.length,
                hasPwd: !!document.querySelector('input[type=password]'),
                cookie: document.cookie.length
              });
            }
            """)
            if let str = probe as? String,
               let d = str.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                hasPost = (o["post"] as? String) == "function"
                if hasPost { break }
                // 最后一次仍没有，把诊断信息带出来
                if attempt == 5 {
                    let url = o["url"] as? String ?? "?"
                    let scripts = o["scripts"] as? Int ?? 0
                    let ready = o["ready"] as? String ?? "?"
                    let pwd = o["hasPwd"] as? Bool ?? false
                    let ax = o["axios"] as? String ?? "?"
                    let pw = pwd ? "有" : "无"
                    lastError = "页面脚本未加载（" + ready + "），脚本数 " + String(scripts)
                        + "，axios=" + ax + "，登录框=" + pw
                    let pv = (o["post"] as? String) ?? "?"
                    let mv = (o["multipost"] as? String) ?? "?"
                    diagInfo = "URL: " + url + "\npost=" + pv + "\nmultipost=" + mv
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if !hasPost {
            // 兜底：页面函数不可用时，直接用 fetch 复刻登录流程
            return await nativeLogin()
        }

        let body = """
        function(){
          return $post('DO_WEB_LOGIN', {username:'\(jsEscape(user))', password:'\(jsEscape(password))'})
            .then(function(res){
              var s = (res && res.data !== undefined) ? String(res.data) : String(res);
              return s;
            });
        }
        """
        let r = await jsCall(body)
        let s = (r as? String) ?? ""

        if s.hasPrefix("0|") {
            ready = true
            lastError = nil
            return true
        }
        if s.hasPrefix("4") {
            lastError = "用户名或密码错误"
        } else if s.hasPrefix("2") || s.hasPrefix("3") {
            lastError = "登录被锁定，请等 1 分钟再试"
        } else if s.isEmpty {
            lastError = "登录无响应，请检查网络连接"
        } else {
            lastError = "登录失败（返回：\(s.prefix(30))）"
        }
        return false
    }

    // MARK: - 原生兜底登录（不依赖页面 $post）

    /// 用页面内 fetch 直接复刻协议：
    /// 1. 取 sessionid
    /// 2. 用 CryptoJS 加密（若可用），否则明文
    /// 3. POST DO_WEB_LOGIN
    private func nativeLogin() async -> Bool {
        guard let (user, password) = loginCreds else { return false }
        let u = jsEscape(user), p = jsEscape(password)

        let js = """
        function(){
          var host = location.origin;
          function rnd(){ return String(Math.random()).replace('0.',''); }
          return fetch(host + '/api/tmp/FHNCAPIS?ajaxmethod=get_refresh_sessionid&_=' + rnd(),
                       {credentials:'include'})
            .then(function(r){ return r.json(); })
            .then(function(o){
              var sid = o.sessionid;
              if (!sid) throw new Error('no_sessionid');
              var inner = JSON.stringify({
                dataObj: {username: 'USER_PLACEHOLDER', password: 'PASS_PLACEHOLDER'},
                ajaxmethod: 'DO_WEB_LOGIN',
                sessionid: sid
              });
              var payload = inner;
              if (typeof CryptoJS !== 'undefined') {
                var key = CryptoJS.enc.Utf8.parse(sid.substring(0,16));
                var iv  = CryptoJS.enc.Utf8.parse('pqrstuvwxyz{|}~');
                var enc = CryptoJS.AES.encrypt(inner, key,
                  {iv: iv, mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7});
                payload = enc.ciphertext.toString(CryptoJS.enc.Hex);
              }
              return fetch(host + '/api/sign/DO_WEB_LOGIN?_' + rnd(), {
                method: 'POST',
                headers: {'Content-Type': 'application/json; charset=utf-8'},
                credentials: 'include',
                body: payload
              }).then(function(r){ return r.text(); });
            })
            .then(function(t){ return t.trim(); });
        }
        """
        // 用占位符替换，避免 Swift 字符串插值被转义破坏
        .replacingOccurrences(of: "USER_PLACEHOLDER", with: u)
        .replacingOccurrences(of: "PASS_PLACEHOLDER", with: p)

        let r = await jsCall(js)
        let str = (r as? String) ?? ""

        if str.hasPrefix("0|") {
            ready = true
            lastError = nil
            diagInfo = "fallback login OK"
            return true
        }
        if str.hasPrefix("4") {
            lastError = "用户名或密码错误"
        } else if str.hasPrefix("2") || str.hasPrefix("3") {
            lastError = "登录被锁定，请等 1 分钟"
        } else if str.isEmpty {
            lastError = "无法获取会话，请确认连着 CPE 的 Wi-Fi"
        } else if str.contains("no_sessionid") {
            lastError = "无法获取会话（设备未响应）"
        } else {
            lastError = "登录失败（" + String(str.prefix(40)) + "）"
        }
        return false
    }

    // MARK: - 通用 JS 调用（带 Promise 支持）

    /// 执行 JS 函数体（字符串形式），返回其结果；支持 Promise
    private func jsCall(_ fnBody: String) async -> Any? {
        guard let wv = webView else { return nil }
        cbSeq += 1
        let cid = "cb\(cbSeq)"

        let result: Any? = await withCheckedContinuation { (cont: CheckedContinuation<Any?, Never>) in
            callbacks[cid] = { v in cont.resume(returning: v) }

            let wrapped = "window.__cpeCall(\(quote(cid)), \(quote(fnBody)));"
            wv.evaluateJavaScript(wrapped) { _, err in
                if let err {
                    Task { @MainActor in
                        if let cb = self.callbacks.removeValue(forKey: cid) {
                            cb(nil)
                        }
                        _ = err
                    }
                }
            }

            // 超时
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                guard let self else { return }
                if let cb = self.callbacks.removeValue(forKey: cid) {
                    cb(nil)
                }
            }
        }
        return result
    }

    private func quote(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let arr = String(data: d, encoding: .utf8) ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())   // 去掉外层 []
    }

    // MARK: - 数据接口

    func fetchValues(_ mapping: [String: String]) async -> [String: String] {
        guard ready else { return [:] }
        let json = (try? JSONSerialization.data(withJSONObject: mapping)) ?? Data("{}".utf8)
        let mapStr = String(data: json, encoding: .utf8) ?? "{}"

        let body = """
        function(){
          return $multipost('get_value_by_xmlnode', \(mapStr))
            .then(function(r){
              var d = (r && r.data_1) ? r.data_1 : (r && r.data ? r.data : r);
              return d || {};
            });
        }
        """
        guard let dict = await jsCall(body) as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in dict {
            if let s = v as? String { out[k] = s }
            else if let n = v as? NSNumber { out[k] = n.stringValue }
        }
        return out
    }

    func multipost(method: String, data: [String: Any]) async -> [[String: Any]] {
        guard ready else { return [] }
        let dj = (try? JSONSerialization.data(withJSONObject: data)) ?? Data("{}".utf8)
        let ds = String(data: dj, encoding: .utf8) ?? "{}"

        let body = """
        function(){
          return $multipost('\(jsEscape(method))', \(ds))
            .then(function(r){
              var d = (r && r.data_1) ? r.data_1 : r;
              if (d && d.data) return d.data;
              if (Array.isArray(d)) return d;
              return [];
            });
        }
        """
        guard let arr = await jsCall(body) as? [[String: Any]] else { return [] }
        return arr
    }

    func setSingle(url: String, value: String) async -> Bool {
        guard ready else { return false }
        let body = """
        function(){
          return $post('set_single_by_xmlnode', {url:'\(jsEscape(url))', value:'\(jsEscape(value))'})
            .then(function(){ return 'OK'; });
        }
        """
        return (await jsCall(body) as? String) == "OK"
    }

    func runCommand(_ key: String) async -> Bool {
        guard ready else { return false }
        let body = """
        function(){
          return $post('do_cmd_web', {key:'\(jsEscape(key))'})
            .then(function(){ return 'OK'; });
        }
        """
        return (await jsCall(body) as? String) == "OK"
    }

    private func jsEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "'", with: "\\'")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "")
    }
}

// MARK: - 消息回调

extension CpeBridge: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let dict = message.body as? String,
              let data = dict.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cid = obj["id"] as? String else { return }

        let payload = obj["payload"] as? [String: Any] ?? [:]
        let ok = payload["ok"] as? Bool ?? false
        let value: Any? = ok ? payload["data"] : nil

        Task { @MainActor in
            if let cb = self.callbacks.removeValue(forKey: cid) {
                cb(value)
            }
        }
    }
}

// MARK: - 导航

extension CpeBridge: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.pageLoaded = true
            guard self.pendingLogin != nil else { return }
            // 稍等，让页面 axios 初始化完成
            try? await Task.sleep(nanoseconds: 400_000_000)
            let ok = await self.doJSLogin()
            self.pendingLogin?.resume(returning: ok)
            self.pendingLogin = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFail navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in
            self.failLogin("无法连接设备：\(error.localizedDescription)")
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in
            self.failLogin("无法连接设备：\(error.localizedDescription)")
        }
    }

    private func failLogin(_ msg: String) {
        lastError = msg
        pendingLogin?.resume(returning: false)
        pendingLogin = nil
    }
}
