import Foundation
import WebKit
import UIKit

/// OPPO CPE 通过隐藏 WKWebView 桥接
///
/// OPPO 的 API 要求 AES-CTR 加密请求体 + MD5 校验和，
/// 全部由页面自身的 JS 处理，我们只负责调用和取结果。
@MainActor
final class OppoBridge: NSObject, ObservableObject {
    static let shared = OppoBridge()

    @Published var ready = false
    @Published var lastError: String?

    private var webView: WKWebView?
    private var host: String = "192.168.0.1"
    private var user: String = "admin"
    private var password: String = ""

    private var callbacks: [String: (Any?) -> Void] = [:]
    private var seq = 0

    private override init() { super.init() }

    // MARK: 建立会话

    func attach(to view: UIView) {
        guard webView == nil else { return }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true

        let ucc = WKUserContentController()
        ucc.add(self, name: "oppoBridge")
        cfg.userContentController = ucc

        // 注入异步桥
        let bootstrap = """
        (function(){
          window.__oppoCall = function(id, fnBody) {
            var finish = function(p){ try {
              window.webkit.messageHandlers.oppoBridge.postMessage(
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
        wv.alpha = 0.01
        wv.isUserInteractionEnabled = false
        view.addSubview(wv)
        wv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wv.widthAnchor.constraint(equalToConstant: 1),
            wv.heightAnchor.constraint(equalToConstant: 1),
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        ])
        webView = wv
    }

    // MARK: 登录

    func login(host: String, user: String, password: String) async -> Bool {
        self.host = host
        self.user = user
        self.password = password
        ready = false

        guard let wv = webView else {
            lastError = "WebView 未初始化"
            return false
        }
        guard let url = URL(string: "http://\(host)/") else {
            lastError = "地址无效"
            return false
        }

        trace.removeAll()
        pageLoaded = false
        loginToken += 1
        let myToken = loginToken
        log("开始加载 \(host)（会话 #\(myToken)）")

        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData
        wv.load(req)

        // 不依赖 didFinish（OPPO 是 SPA，加载慢），主动轮询等待输入框
        // 注意：jsCall 在页面未就绪时可能返回 nil，必须记录否则看不出问题
        let t0 = Date()

        // 阶段一：等 didFinish（最多 20 秒）
        var waited = 0.0
        while !pageLoaded && waited < 20 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if loginToken != myToken { log("被新登录中断"); return false }
            waited += 0.3
        }
        log(pageLoaded ? "didFinish \(Int(waited))s" : "✗ didFinish 超时 20s")

        // 阶段二：轮询探测输入框（最多 15 秒）
        var lastReport = -1
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if loginToken != myToken { log("被新登录中断"); return false }
            let elapsed = Int(Date().timeIntervalSince(t0))

            let st = await jsCall("""
            function(){
              return JSON.stringify({
                inputs: document.querySelectorAll('input').length,
                hash: location.hash,
                ready: document.readyState,
                body: (document.body ? document.body.innerHTML.length : 0)
              });
            }
            """)

            guard let str = st as? String else {
                // 关键：nil 说明 evaluateJavaScript 失败（页面还在加载或已崩溃）
                if elapsed / 5 != lastReport {
                    lastReport = elapsed / 5
                    log("\(elapsed)s: 页面无响应")
                }
                continue
            }
            guard let d = str.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                if elapsed / 5 != lastReport {
                    lastReport = elapsed / 5
                    log("\(elapsed)s: 解析失败")
                }
                continue
            }

            let inputs = o["inputs"] as? Int ?? 0
            if elapsed / 5 != lastReport {
                lastReport = elapsed / 5
                log("\(elapsed)s: inputs=\(inputs) hash=\(o["hash"] ?? "?") body=\(o["body"] ?? 0)")
            }

            if inputs >= 2 {
                log("页面就绪 (\(elapsed)s)")
                return await doLogin()
            }
        }

        lastError = "页面加载超时，请确认连的是 OPPO CPE 的 Wi-Fi"
        log("✗ 30 秒内未渲染出登录框")
        return false
    }

    /// 诊断日志
    private(set) var trace: [String] = []
    /// 页面是否已加载完成（didFinish 触发）
    private var pageLoaded = false
    /// 登录会话令牌：新登录会让旧的轮询循环自行退出
    private var loginToken = 0
    private func log(_ s: String) {
        trace.append(s)
        if trace.count > 30 { trace.removeFirst() }
    }

    private func doLogin() async -> Bool {
        trace.removeAll()
        log("页面加载完成")

        // 等 Vue 渲染出输入框
        var inputReady = false
        var lastState = ""
        for i in 0..<15 {
            let st = await jsCall("""
            function(){
              return JSON.stringify({
                inputs: document.querySelectorAll('input').length,
                hash: location.hash,
                ready: document.readyState,
                bodyLen: (document.body ? document.body.innerHTML.length : 0),
                hasBridge: typeof window.__oppoCall
              });
            }
            """)
            lastState = (st as? String) ?? "(nil)"
            if let str = st as? String,
               let d = str.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let n = o["inputs"] as? Int, n >= 2 {
                inputReady = true
                log("输入框就绪 (\(i * 400)ms)")
                break
            }
            if i == 0 || i == 5 || i == 14 {
                log("探测\(i): \(lastState)")
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        if !inputReady {
            log("✗ 最终状态: \(lastState)")
            lastError = "页面未渲染登录框（\(lastState)）"
            return false
        }

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
              setter.call(ins[1], '\(jsEscape(password))');
              ins[1].dispatchEvent(new Event('input', {bubbles:true}));

              setTimeout(function(){
                var btn = Array.prototype.slice.call(
                  document.querySelectorAll('button')).filter(function(b){
                    return /LOGIN|登录/i.test(b.textContent);
                  })[0];
                if (btn) btn.click();
                setTimeout(function(){ resolve(location.hash); }, 2500);
              }, 400);
            } catch(e) { resolve('ERR:' + e.message); }
          });
        }
        """
        let r = await jsCall(body)
        let hash = (r as? String) ?? ""
        log("提交后 hash: \(hash)")

        if hash.contains("login") {
            lastError = "用户名或密码错误"
            return false
        }
        if hash.hasPrefix("ERR") || hash == "NO_INPUT" {
            lastError = "页面状态异常：" + hash
            return false
        }
        ready = true
        return true
    }

    // MARK: 数据读取

    /// 读取首页仪表盘的所有文本（OPPO 没有简单 JSON 接口，直接解析 DOM）
    func fetchDashboard() async -> [String: String] {
        guard ready else { return [:] }

        // 只在 JS 侧取一次 innerText，就地提取需要的行，减少跨进程传输
        // 分隔符用 ||| 和 ###，避免 Swift 字符串转义冲突
        let body = """
        function(){
          var t = document.body.innerText;
          if (!t) return '';
          var lines = t.split('\n');
          var out = [];
          var want = {};
          ['UL Data Rate','DL Data Rate','RSRP','RSRQ','SINR','PCI',
           'Frequency Band','Network Status','Carrier Aggregation',
           'Total','Upload','Download','Device Name','Serial Number',
           'Software Version','Hardware Version','Manufacturer Info',
           'System Uptime','CPU Usage','Memory Usage',
           'SSID 2.4 GHz','SSID 5 GHz','PLMN'].forEach(function(k){ want[k]=1; });
          for (var i = 0; i < lines.length; i++) {
            var l = lines[i].trim();
            if (want[l] && i + 1 < lines.length) {
              out.push(l + '###' + lines[i+1].trim());
            }
          }
          var m = t.match(/total of ([0-9]+) devices?/);
          if (m) out.push('_deviceCount###' + m[1]);
          return out.join('|||');
        }
        """
        let raw = (await jsCall(body) as? String) ?? ""
        guard !raw.isEmpty else { return [:] }

        // 解析成字典
        var d: [String: String] = [:]
        for pair in raw.components(separatedBy: "|||") {
            let kv = pair.components(separatedBy: "###")
            guard kv.count == 2 else { continue }
            d[kv[0]] = kv[1]
        }
        if let n = d["_deviceCount"] { d["deviceCount"] = n }

        return OppoParser.parseFromPairs(d)
    }

    /// 调用 NetStats/GetStats 拿精确流量与实时速率
    /// 返回：BytesReceived / BytesSent / RateReceived / RateSent
    func fetchStats() async -> [String: Any] {
        guard ready else { return [:] }

        let body = """
        function(){
          // 从 Vue 根实例拿带拦截器的 axios
          var app = document.querySelector('#app');
          var vm = app && app.__vue__;
          var ax = null;
          (function walk(v, d){
            if (!v || d > 6 || ax) return;
            if (v.$http) { ax = v.$http; return; }
            (v.$children || []).forEach(function(c){ walk(c, d+1); });
          })(vm, 0);
          if (!ax) return JSON.stringify({error:'no_axios'});

          return ax.post('/NetStats/GetStats', {}).then(function(r){
            var s = r && r.Stats && r.Stats[0];
            if (!s) return JSON.stringify({error:'no_stats'});
            return JSON.stringify({
              rx: s.BytesReceived,
              tx: s.BytesSent,
              rateRx: s.RateReceived,
              rateTx: s.RateSent
            });
          });
        }
        """
        guard let str = await jsCall(body) as? String,
              let d = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    // MARK: 底层

    private func jsCall(_ fn: String) async -> Any? {
        guard let wv = webView else { return nil }
        seq += 1
        let cid = "o\(seq)"

        return await withCheckedContinuation { (cont: CheckedContinuation<Any?, Never>) in
            callbacks[cid] = { cont.resume(returning: $0) }
            let wrapped = "window.__oppoCall(\(quote(cid)), \(quote(fn)));"
            wv.evaluateJavaScript(wrapped) { _, err in
                if let err = err {
                    Task { @MainActor in
                        self.log("jsCall 错误: \(err.localizedDescription)")
                        if let cb = self.callbacks.removeValue(forKey: cid) { cb(nil) }
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
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
    }
}

extension OppoBridge: WKScriptMessageHandler {
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

extension OppoBridge: WKNavigationDelegate {
    nonisolated func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        Task { @MainActor in
            self.pageLoaded = true
            self.log("didFinish: \(wv.url?.absoluteString ?? "?")")
        }
    }

    nonisolated func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError e: Error) {
        Task { @MainActor in self.fail(e) }
    }
    nonisolated func webView(_ wv: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError e: Error) {
        Task { @MainActor in self.fail(e) }
    }

    private func fail(_ e: Error) {
        log("✗ 加载失败: \(e.localizedDescription)")
    }
}
