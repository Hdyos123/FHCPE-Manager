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

        // 先确认页面上的函数是否就绪
        let probe = await jsCall("function(){ return (typeof $post === 'function') ? 'yes' : 'no'; }")
        let hasPost = (probe as? String) == "yes"
        if !hasPost {
            lastError = "页面脚本未就绪（可能需要允许本地网络权限）"
            return false
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
