import SwiftUI
import WebKit

// Pocket 网页容器：加载用户配置的地址。
// 注意实现 createWebViewWith：官方远控的 window.open / _blank 链接都在本视图内打开。
struct PocketWebView: UIViewRepresentable {
    let url: URL
    @EnvironmentObject var state: AppState

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.isPagingEnabled = false
        wv.load(URLRequest(url: url))
        state.webView = wv
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let state: AppState
        init(state: AppState) { self.state = state }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // _blank/window.open 一律在当前视图打开（官方远控「打开」按钮走这里）
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.isLoading = false
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.isLoading = true
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
        }
    }
}
