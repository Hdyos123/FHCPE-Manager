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
    private var pendingLogin: CheckedContinuation<Bool, Never>?

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
        guard let url = URL(string: "http://\(host)/#/login") else {
            lastError = "地址无效"
            return false
        }

        return await withCheckedContinuation { cont in
            pendingLogin = cont
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            wv.load(req)

            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
                guard let self, let p = self.pendingLogin else { return }
                self.pendingLogin = nil
                self.lastError = "连接超时，请确认已连接 OPPO CPE 的 Wi-Fi"
                p.resume(returning: false)
            }
        }
    }

    private func doLogin() async -> Bool {
        // 等 Vue 渲染出输入框
        for _ in 0..<10 {
            let ok = await jsCall("function(){ return document.querySelectorAll('input').length >= 2; }")
            if (ok as? Bool) == true { break }
            try? await Task.sleep(nanoseconds: 400_000_000)
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

        // 只在 JS 侧取一次 innerText，然后就地提取需要的行，减少跨进程传输
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
              out.push(l + '\u0001' + lines[i+1].trim());
            }
          }
          // 设备总数
          var m = t.match(/total of (\d+) devices?/);
          if (m) out.push('_deviceCount\u0001' + m[1]);
          return out.join('\u0002');
        }
        """
        let raw = (await jsCall(body) as? String) ?? ""
        guard !raw.isEmpty else { return [:] }

        // 解析成字典（ 分隔条目， 分隔键值）
        var d: [String: String] = [:]
        for pair in raw.components(separatedBy: "\u{0002}") {
            let kv = pair.components(separatedBy: "\u{0001}")
            guard kv.count == 2 else { continue }
            d[kv[0]] = kv[1]
        }
        if let n = d["_deviceCount"] { d["deviceCount"] = n }

        // 复用原有的映射逻辑
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
            wv.evaluateJavaScript(wrapped) { _, _ in }

            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
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
            guard self.pendingLogin != nil else { return }
            let ok = await self.doLogin()
            self.pendingLogin?.resume(returning: ok)
            self.pendingLogin = nil
        }
    }

    nonisolated func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError e: Error) {
        Task { @MainActor in self.fail(e) }
    }
    nonisolated func webView(_ wv: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError e: Error) {
        Task { @MainActor in self.fail(e) }
    }

    private func fail(_ e: Error) {
        lastError = "无法连接设备：" + e.localizedDescription
        pendingLogin?.resume(returning: false)
        pendingLogin = nil
    }
}
