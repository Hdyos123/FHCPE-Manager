import Foundation
import WebKit
import UIKit

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

    private var callbacks: [String: (Any?) -> Void] = [:]
    private var seq = 0

    private override init() { super.init() }

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
        wv.alpha = 0.02
        wv.isUserInteractionEnabled = false
        view.addSubview(wv)
        wv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wv.widthAnchor.constraint(equalToConstant: 2),
            wv.heightAnchor.constraint(equalToConstant: 2),
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        ])
        webView = wv
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
            lastError = "WebView 未初始化"
            return false
        }
        guard let url = URL(string: "http://\(host)/") else {
            lastError = "地址无效"
            return false
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData
        wv.load(req)

        var waited = 0.0
        while !pageLoaded && waited < 25 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            waited += 0.3
        }
        log(pageLoaded ? "didFinish \(Int(waited))s" : "✗ didFinish 超时")

        // 等 Vue 渲染出登录框
        var ok = false
        for i in 0..<40 {
            let st = await jsCall("""
            function(){
              return JSON.stringify({
                inputs: document.querySelectorAll('input').length,
                hash: location.hash
              });
            }
            """)
            if let s = st as? String,
               let d = s.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let n = o["inputs"] as? Int, n >= 2 {
                ok = true
                log("页面就绪 (\(i/2)s)")
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard ok else {
            lastError = "页面未渲染登录框"
            return false
        }

        // 如果已经在登录后页面，跳过登录
        if await isLoggedIn() {
            ready = true
            log("已有会话，直接使用")
            return true
        }

        return await doLogin()
    }

    /// 判断页面是否已登录（能取到 $request）
    private func isLoggedIn() async -> Bool {
        let r = await jsCall("""
        function(){
          try {
            var app = document.querySelector('#app');
            if (!app || !app.__vue_app__) return 'no_app';
            var gp = app.__vue_app__.config.globalProperties;
            if (gp && gp.$request) return 'yes';
            var h = location.hash || '';
            if (/home|Home/i.test(h)) return 'yes';
            return 'no';
          } catch(e) { return 'err'; }
        }
        """)
        return (r as? String) == "yes"
    }

    private func doLogin() async -> Bool {
        let body = """
        function(){
          return new Promise(function(resolve){
            try {
              var ins = document.querySelectorAll('input');
              if (ins.length < 2) { resolve('NO_INPUT'); return; }
              var setter = Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'value').set;
              setter.call(ins[0], '\(jsEscape(user))');
              ins[0].dispatchEvent(new Event('input', {bubbles:true}));
              setter.call(ins[1], '\(jsEscape(pass))');
              ins[1].dispatchEvent(new Event('input', {bubbles:true}));
              ins[1].dispatchEvent(new Event('change', {bubbles:true}));

              setTimeout(function(){
                var btn = Array.prototype.slice.call(
                  document.querySelectorAll('button')).filter(function(b){
                    return /登录|Login|LOGIN/i.test(b.textContent || '');
                  })[0];
                if (btn) btn.click();
                setTimeout(function(){ resolve(location.hash); }, 5000);
              }, 700);
            } catch(e) { resolve('ERR:' + e.message); }
          });
        }
        """
        let r = await jsCall(body, timeout: 12)
        let hash = (r as? String) ?? ""
        log("登录后 hash: \(hash)")

        if hash.hasPrefix("ERR") || hash == "NO_INPUT" {
            lastError = "登录失败：\(hash)"
            return false
        }
        if hash.contains("login") || hash.contains("Login") {
            lastError = "用户名或密码错误"
            return false
        }

        // 等 $request 就绪
        for _ in 0..<10 {
            if await isLoggedIn() {
                ready = true
                log("✓ 登录成功")
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        ready = true
        log("✓ 页面已跳转")
        return true
    }

    // MARK: 调用设备 API

    /// GET 请求（用页面内部别名，如 hostList / singal / monitoringStatus）
    func get(_ alias: String) async -> [String: Any] {
        let js = """
        function(){
          return new Promise(function(resolve){
            try {
              var app = document.querySelector('#app');
              var gp = app && app.__vue_app__ && app.__vue_app__.config.globalProperties;
              var R = gp && gp.$request;
              if (!R) { resolve(JSON.stringify({__err:'NO_REQUEST'})); return; }
              R.$get('\(jsEscape(alias))', {}).then(function(r){
                if (r && r.error) {
                  resolve(JSON.stringify({__err:String(r.error.code||'?')}));
                  return;
                }
                var o = r && r.response !== undefined ? r.response : r;
                resolve(JSON.stringify(o || {}));
              }).catch(function(e){
                resolve(JSON.stringify({__err:String(e && e.message)}));
              });
            } catch(e) { resolve(JSON.stringify({__err:'EXC:'+e.message})); }
          });
        }
        """
        guard let s = await jsCall(js, timeout: 12) as? String,
              let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return [:]
        }
        if let e = o["__err"] as? String { return ["__err": e] }
        return o
    }

    /// POST 请求
    func post(_ alias: String, _ body: [String: Any]) async -> [String: Any] {
        let bd = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        let bs = String(data: bd, encoding: .utf8) ?? "{}"

        let js = """
        function(){
          return new Promise(function(resolve){
            try {
              var app = document.querySelector('#app');
              var gp = app && app.__vue_app__ && app.__vue_app__.config.globalProperties;
              var R = gp && gp.$request;
              if (!R) { resolve(JSON.stringify({__err:'NO_REQUEST'})); return; }
              R.$post('\(jsEscape(alias))', \(bs)).then(function(r){
                if (r && r.error) {
                  resolve(JSON.stringify({__err:String(r.error.code||'?')}));
                  return;
                }
                var o = r && r.response !== undefined ? r.response : r;
                resolve(JSON.stringify(o || {}));
              }).catch(function(e){
                resolve(JSON.stringify({__err:String(e && e.message)}));
              });
            } catch(e) { resolve(JSON.stringify({__err:'EXC:'+e.message})); }
          });
        }
        """
        guard let s = await jsCall(js, timeout: 15) as? String,
              let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return [:]
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
}
