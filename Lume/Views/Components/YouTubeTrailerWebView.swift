import SwiftUI
import WebKit

/// A WKWebView-based YouTube player that embeds a video in a cinematic,
/// chromeless configuration: autoplay, muted, looped, no UI elements.
struct YouTubeTrailerWebView: NSViewRepresentable {
    let videoId: String
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // Allow YouTube embeds by setting appropriate preferences
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        
        loadVideo(in: webView)
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    private func loadVideo(in webView: WKWebView) {
        // Use youtube-nocookie.com for privacy-enhanced embed mode.
        // This domain is more permissive with embedding contexts.
        // Parameters:
        //   autoplay=1    : auto-start
        //   mute=1        : muted (required for autoplay)
        //   loop=1        : loop forever
        //   playlist=ID   : required for loop to work with single video
        //   controls=0    : hide player controls
        //   showinfo=0    : hide title bar
        //   rel=0         : no related videos at end
        //   modestbranding=1 : minimal YouTube branding
        //   iv_load_policy=3 : no annotations
        //   disablekb=1   : disable keyboard shortcuts
        //   playsinline=1 : inline playback
        //   fs=0          : disable fullscreen button
        //   cc_load_policy=0 : hide closed captions
        
        let embedURL = "https://www.youtube-nocookie.com/embed/\(videoId)?autoplay=1&mute=1&loop=1&playlist=\(videoId)&controls=0&showinfo=0&rel=0&modestbranding=1&iv_load_policy=3&disablekb=1&playsinline=1&fs=0&cc_load_policy=0"
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            * { margin: 0; padding: 0; overflow: hidden; }
            html, body { width: 100%; height: 100%; background: transparent; }
            .video-wrap {
                position: absolute;
                top: 50%; left: 50%;
                width: 177.78vh; /* 16:9 aspect ratio */
                height: 100vh;
                min-width: 100vw;
                min-height: 56.25vw; /* 16:9 aspect ratio */
                transform: translate(-50%, -50%);
            }
            iframe {
                width: 100%;
                height: 100%;
                border: 0;
                pointer-events: none;
            }
        </style>
        </head>
        <body>
        <div class="video-wrap">
            <iframe
                src="\(embedURL)"
                allow="autoplay; encrypted-media"
                allowfullscreen="false"
                frameborder="0">
            </iframe>
        </div>
        </body>
        </html>
        """
        
        // Load with youtube-nocookie.com as the base URL so the embed origin matches
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let allowed = url.absoluteString.contains("youtube") || 
                              url.absoluteString.contains("googlevideo.com") ||
                              url.absoluteString.contains("google.com") ||
                              url.absoluteString.starts(with: "about:")
                decisionHandler(allowed ? .allow : .cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
