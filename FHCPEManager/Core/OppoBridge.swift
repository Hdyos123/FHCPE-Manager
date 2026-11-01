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
        // 关键：允许 JS 在不活跃时也执行
        cfg.suppressesIncrementalRendering = false
        if #available(iOS 15.0, *) {
            // 允许页面在后台继续运行脚本
            cfg.preferences.isElementFullscreenEnabled = false
        }
        cfg.processPool = WKProcessPool()

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
        wv.alpha = 0.02   // 不能为 0，否则 WebKit 暂停 JS
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
        log(pageLoaded ? "didFinish \(Int(waited))s" : "X didFinish 超时 20s")

        // 关键诊断：JS 引擎是否可用
        let jsOK = await selfTest()
        log("JS 自检: " + jsOK)
        if jsOK.hasPrefix("X") {
            log("→ WebView 引擎不可用，此设备无法使用 WebView 方案")
            return false
        }

        // 阶段二：轮询探测输入框（最多 15 秒）
        var lastReport = -1
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if loginToken != myToken { log("被新登录中断"); return false }
            let elapsed = Int(Date().timeIntervalSince(t0))

            // 用 evalDirect（直接 evaluateJavaScript），不走 __oppoCall 桥
            let st = await evalDirect("""
            (function(){
              return JSON.stringify({
                inputs: document.querySelectorAll('input').length,
                hash: location.hash,
                ready: document.readyState,
                body: (document.body ? document.body.innerHTML.length : 0)
              });
            })()
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
            let st = await evalDirect("""
            (function(){
              return JSON.stringify({
                inputs: document.querySelectorAll('input').length,
                hash: location.hash,
                ready: document.readyState,
                bodyLen: (document.body ? document.body.innerHTML.length : 0),
                hasBridge: typeof window.__oppoCall
              });
            })()
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

        // 用 evalDirect 执行，但 Promise 需要额外等待——改成轮询 hash
        _ = await evalDirect("""
        (function(){
          try {
            var ins = document.querySelectorAll('input');
            if (ins.length < 2) return 'NO_INPUT';
            var setter = Object.getOwnPropertyDescriptor(
              window.HTMLInputElement.prototype, 'value').set;
            setter.call(ins[0], '\(jsEscape(user))');
            ins[0].dispatchEvent(new Event('input', {bubbles:true}));
            setter.call(ins[1], '\(jsEscape(password))');
            ins[1].dispatchEvent(new Event('input', {bubbles:true}));
            setTimeout(function(){
              var btn = Array.prototype.slice.call(
                document.querySelectorAll('button')).filter(function(b){
                  return /LOGIN/i.test(b.textContent);
                })[0];
              if (btn) btn.click();
            }, 400);
            return 'SUBMITTED';
          } catch(e) { return 'ERR:' + e.message; }
        })()
        """, timeout: 5)

        // 等待跳转（最多 5 秒，一检测到就返回）
        var hash = ""
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let h = await evalDirect("location.hash", timeout: 1) ?? ""
            hash = h
            if !h.contains("login") && !h.isEmpty { break }
        }
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
        (function(){
          var t = document.body.innerText;
          if (!t) return '';
          var lines = t.split(String.fromCharCode(10));
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
        })()
        """
        let raw = await evalDirect(body) ?? ""
        guard !raw.isEmpty else {
            log("XDashboard 返回空")
            // 诊断：单独读一次 innerText 看长度
            let len = await evalDirect("(document.body ? document.body.innerText.length : -1)") ?? "nil"
            log("  innerText 长度: " + len)
            return [:]
        }
        log("Dashboard 拿到 " + String(raw.count) + " 字符")

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

    /// 只读取页面上的「实时上传/下载速率」
    /// 比 innerText 快得多：只查特定文本节点，不触发全页重排
    func fetchSpeeds() async -> (rx: Double, tx: Double) {
        guard ready else { return (0, 0) }

        let js = """
        (function(){
          var result = {dl: 0, ul: 0};
          var els = document.querySelectorAll('div, span, p, td, dd');
          for (var i = 0; i < els.length; i++) {
            var t = (els[i].textContent || '').trim();
            if (t !== 'DL Data Rate' && t !== 'UL Data Rate') continue;
            var box = els[i].parentElement;
            if (!box) continue;
            var txt = box.textContent || '';
            var m = txt.match(/([0-9.]+)[ ]*([KMGT]?)bps/i);
            if (!m) continue;
            var val = parseFloat(m[1]);
            var unit = m[2].toUpperCase();
            if (unit === 'K') val /= 1000;
            else if (unit === 'G') val *= 1000;
            else if (unit === 'T') val *= 1000000;
            if (t === 'DL Data Rate') result.dl = val;
            else result.ul = val;
          }
          return JSON.stringify(result);
        })()
        """

        guard let str = await evalDirect(js, timeout: 2),
              let d = str.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return (0, 0)
        }
        let dl = (o["dl"] as? NSNumber)?.doubleValue ?? 0
        let ul = (o["ul"] as? NSNumber)?.doubleValue ?? 0
        return (dl, ul)
    }

    /// 调用 NetStats/GetStats 拿精确流量与实时速率
    /// 返回：BytesReceived / BytesSent / RateReceived / RateSent
    func fetchStats() async -> [String: Any] {
        guard ready else { return [:] }

        // Promise 结果写到全局变量，再轮询读取
        _ = await evalDirect("""
        (function(){
          window.__statsResult = null;
          try {
            var app = document.querySelector('#app');
            var vm = app && app.__vue__;
            var ax = null;
            (function walk(v, d){
              if (!v || d > 6 || ax) return;
              if (v.$http) { ax = v.$http; return; }
              (v.$children || []).forEach(function(c){ walk(c, d+1); });
            })(vm, 0);
            if (!ax) { window.__statsResult = '{"error":"no_axios"}'; return 'ok'; }
            ax.post('/NetStats/GetStats', {}).then(function(r){
              var s = r && r.Stats && r.Stats[0];
              window.__statsResult = s ? JSON.stringify({
                rx: s.BytesReceived, tx: s.BytesSent,
                rateRx: s.RateReceived, rateTx: s.RateSent
              }) : '{"error":"no_stats"}';
            }).catch(function(e){ window.__statsResult = '{"error":"' + String(e) + '"}'; });
            return 'ok';
          } catch(e) { window.__statsResult = '{"error":"' + e.message + '"}'; return 'ok'; }
        })()
        """, timeout: 5)

        // 轮询读取结果
        var str: String?
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            str = await evalDirect("window.__statsResult || ''", timeout: 2)
            if let v = str, !v.isEmpty, v != "null" { break }
        }
        guard let str = str,
              let d = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    // MARK: 底层

    /// 直接执行 JS 并返回结果（不依赖 __oppoCall 注入脚本）
    /// 用于页面脚本注入失效时的兜底
    func evalDirect(_ js: String, timeout: TimeInterval = 3) async -> String? {
        guard let wv = webView else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            var done = false
            let lock = NSLock()
            let finish: (String?) -> Void = { v in
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                c.resume(returning: v)
            }
            wv.evaluateJavaScript(js) { r, e in
                if e != nil { finish(nil) }
                else if let s = r as? String { finish(s) }
                else if let r = r { finish(String(describing: r)) }
                else { finish(nil) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }

    /// 自检：验证 WebView 的 JS 引擎能否执行
    func selfTest() async -> String {
        guard let wv = webView else { return "X WebView 未初始化" }

        return await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            var done = false
            let lock = NSLock()
            let finish: (String) -> Void = { v in
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                c.resume(returning: v)
            }
            wv.evaluateJavaScript("1+1") { r, e in
                if let e = e { finish("X JS 错误: " + e.localizedDescription) }
                else { finish("OK JS 可用, 结果=" + String(describing: r)) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish("X JS 超时(3s) - 引擎被暂停") }
        }
    }

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
