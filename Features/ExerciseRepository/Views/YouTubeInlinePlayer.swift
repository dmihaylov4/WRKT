import SwiftUI
import WebKit
import AVFoundation

struct YouTubePlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []            // user gesture not required
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true // ensure JS runs

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.navigationDelegate = context.coordinator

        // Optional (but helps with silent switch / background mixes)
        try? AVAudioSession.sharedInstance().setCategory(.playback,
                                                         mode: .moviePlayback,
                                                         options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let embed = Self.embedURL(for: url)
        let html = """
        <!doctype html>
        <html><head>
          <meta name="viewport" content="initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
          <style>
            html,body{margin:0;background:transparent;height:100%}
            .wrap{position:relative;padding-top:56.25%}
            iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}
          </style>
        </head><body>
          <div class="wrap">
            <iframe
               src="\(embed.absoluteString)"
               allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
               allowfullscreen
               referrerpolicy="strict-origin-when-cross-origin">
            </iframe>
          </div>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("YouTube nav error:", error)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("YouTube provisional error:", error)
        }
    }

    // MARK: URL helpers
    private static func embedURL(for url: URL) -> URL {
        if let id = videoID(from: url) {
            // modestbranding/rel keep the UI clean; playsinline avoids FS handoff from sheets
            let qs = "playsinline=1&modestbranding=1&rel=0&controls=1"
            return URL(string: "https://www.youtube.com/embed/\(id)?\(qs)")!
        }
        return url // already an /embed URL
    }

    private static func videoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("youtu.be") { return url.lastPathComponent }
        if host.contains("youtube.com") {
            if url.path.contains("/embed/")     { return url.lastPathComponent }
            if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value { return v }
        }
        return nil
    }
}
