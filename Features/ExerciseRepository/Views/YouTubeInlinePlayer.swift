import SwiftUI
import WebKit
import OSLog

// MARK: - Public Wrapper with Error Handling

struct YouTubePlayerView: View {
    let url: URL
    @State private var showError = false

    var body: some View {
        ZStack {
            YouTubeWebView(url: url, showError: $showError)
                .opacity(showError ? 0 : 1)

            // Fallback UI when video can't be embedded
            if showError {
                VStack(spacing: 16) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Video Unavailable")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("This video cannot be embedded")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Link(destination: url) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Watch on YouTube")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.blue)
                        .clipShape(Capsule())
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGray6))
            }
        }
    }
}

// MARK: - Internal WebView Implementation

private struct YouTubeWebView: UIViewRepresentable {
    let url: URL
    @Binding var showError: Bool

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        // Create webpage preferences
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        cfg.defaultWebpagePreferences = prefs

        // Add user content controller for JavaScript messages
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "errorHandler")
        cfg.userContentController = controller

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.navigationDelegate = context.coordinator

        // Allow loading of embedded content
        if #available(iOS 16.4, *) {
            wv.isInspectable = true  // Enable web inspector for debugging
        }

        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Skip if already loaded
        guard webView.url == nil || webView.url?.absoluteString.contains("youtube") == false else {
            return
        }

        let embed = Self.embedURL(for: url)

        if let videoID = Self.videoID(from: url) {
            AppLogger.debug("Loading YouTube video ID: \(videoID)", category: AppLogger.network)
        }

        // Load the YouTube embed URL directly
        let request = URLRequest(url: embed)
        webView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(showError: $showError)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var showError: Bool
        private var loadTimeout: Timer?

        init(showError: Binding<Bool>) {
            self._showError = showError
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            AppLogger.error("YouTube nav error: \(error.localizedDescription)", category: AppLogger.network)
            DispatchQueue.main.async {
                self.showError = true
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            AppLogger.error("YouTube provisional error: \(error.localizedDescription)", category: AppLogger.network)
            DispatchQueue.main.async {
                self.showError = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            AppLogger.debug("YouTube player loaded successfully", category: AppLogger.network)

            // Check for YouTube player errors after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self, weak webView] in
                guard let webView = webView else { return }

                // Inject JavaScript to check for error message
                let js = """
                (function() {
                    const errorDiv = document.querySelector('.ytp-error');
                    const errorMessage = document.querySelector('.ytp-error-content-wrap');
                    if (errorDiv || errorMessage) {
                        return 'error';
                    }
                    return 'ok';
                })();
                """

                webView.evaluateJavaScript(js) { result, error in
                    if let result = result as? String, result == "error" {
                        AppLogger.warning("YouTube player error detected (likely embedding disabled)", category: AppLogger.network)
                        DispatchQueue.main.async {
                            self?.showError = true
                        }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation for YouTube embeds
            decisionHandler(.allow)
        }

        // Handle JavaScript messages
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "errorHandler" {
                AppLogger.warning("YouTube error message received: \(message.body)", category: AppLogger.network)
                DispatchQueue.main.async {
                    self.showError = true
                }
            }
        }
    }

    // MARK: URL helpers
    private static func embedURL(for url: URL) -> URL {
        if let id = videoID(from: url) {
            // Optimized embed parameters for iOS WKWebView direct loading:
            // - playsinline=1: Essential for inline playback on iOS
            // - modestbranding=1: Cleaner player UI
            // - rel=0: Don't show related videos
            // - enablejsapi=0: Disable JS API (we're not using it, reduces complexity)
            // Note: Some videos have embedding disabled by owner - cannot be bypassed
            let qs = "playsinline=1&modestbranding=1&rel=0&enablejsapi=0"
            return URL(string: "https://www.youtube.com/embed/\(id)?\(qs)")!
        }
        return url // already an /embed URL
    }

    private static func videoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        // Handle youtu.be short URLs
        if host.contains("youtu.be") {
            // Remove leading slash and any query parameters
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // Split by ? to remove query params like ?si=...
            if let id = path.split(separator: "?").first {
                return String(id)
            }
            return path.isEmpty ? nil : path
        }

        // Handle youtube.com URLs
        if host.contains("youtube.com") {
            // Handle /embed/ URLs
            if url.path.contains("/embed/") {
                let components = url.path.components(separatedBy: "/")
                if let embedIndex = components.firstIndex(of: "embed"),
                   embedIndex + 1 < components.count {
                    return components[embedIndex + 1]
                }
            }
            // Handle /watch?v= URLs
            if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value {
                return v
            }
        }
        return nil
    }
}
