import SwiftUI
import WebKit
import OSLog

// MARK: - YouTube In-App Player

struct YouTubePlayerView: View {
    let url: URL
    @State private var showPlayer = false
    @State private var thumbnailURL: URL?

    var body: some View {
        if showPlayer {
            YouTubeWebPlayer(url: url, onClose: { showPlayer = false })
        } else {
            YouTubePreviewCard(
                url: url,
                thumbnailURL: thumbnailURL,
                onTap: { showPlayer = true }
            )
            .onAppear {
                if let videoID = extractVideoID(from: url) {
                    thumbnailURL = URL(string: "https://img.youtube.com/vi/\(videoID)/maxresdefault.jpg")
                }
            }
        }
    }

    private func extractVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        // Handle youtu.be short URLs
        if host.contains("youtu.be") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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

// MARK: - YouTube Web Player

private struct YouTubeWebPlayer: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Close button
            HStack {
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .black.opacity(0.7))
                        .padding(8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .background(Color.black)

            // YouTube player
            if let videoID = extractVideoID(from: url) {
                YouTubeWebView(videoID: videoID)
            }
        }
        .background(Color.black)
    }

    private func extractVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        if host.contains("youtu.be") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let id = path.split(separator: "?").first {
                return String(id)
            }
            return path.isEmpty ? nil : path
        }

        if host.contains("youtube.com") {
            if url.path.contains("/embed/") {
                let components = url.path.components(separatedBy: "/")
                if let embedIndex = components.firstIndex(of: "embed"),
                   embedIndex + 1 < components.count {
                    return components[embedIndex + 1]
                }
            }
            if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value {
                return v
            }
        }
        return nil
    }
}

// MARK: - YouTube WebKit View

private struct YouTubeWebView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = false

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let embedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body { margin: 0; padding: 0; background: #000; overflow: hidden; }
                .video-container { position: relative; width: 100%; height: 100vh; }
                iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: 0; }
            </style>
        </head>
        <body>
            <div class="video-container">
                <iframe
                    src="https://www.youtube.com/embed/\(videoID)?autoplay=1&playsinline=1&rel=0&modestbranding=1"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                    allowfullscreen>
                </iframe>
            </div>
        </body>
        </html>
        """

        webView.loadHTMLString(embedHTML, baseURL: nil)
    }
}

// MARK: - YouTube Preview Card

private struct YouTubePreviewCard: View {
    let url: URL
    let thumbnailURL: URL?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Thumbnail background
                if let thumbnailURL = thumbnailURL {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .empty:
                            Color.black
                                .overlay {
                                    ProgressView()
                                        .tint(.white)
                                }
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            fallbackThumbnail
                        @unknown default:
                            fallbackThumbnail
                        }
                    }
                } else {
                    fallbackThumbnail
                }

                // Play button overlay
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.7))
                        .frame(width: 72, height: 72)

                    Image(systemName: "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 3) // Optical alignment
                }

                // In-app badge
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.caption2)
                            Text("Tap to Play")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var fallbackThumbnail: some View {
        ZStack {
            Color.black
            VStack(spacing: 8) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Tap to Watch")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

