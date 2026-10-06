import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct PreviewView: NSViewRepresentable {
    var markdown: String
    var baseDirectory: URL?
    var fontFamily: PreviewFont
    var fontSize: Double
    /// 0…1 scroll position to mirror from the editor, or nil to leave it alone.
    var scrollFraction: Double?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Page scripts are off: the preview is driven entirely via callAsyncJavaScript.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LocalFileSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .textBackgroundColor
        webView.allowsMagnification = true
        webView.setAccessibilityLabel("Preview")
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let style = PreviewStyle(font: fontFamily, size: fontSize)
        if coordinator.loadedBase != baseDirectory || coordinator.loadedStyle != style || !coordinator.hasLoaded {
            coordinator.load(base: baseDirectory, style: style)
        }
        coordinator.update(markdown: markdown)
        if let scrollFraction, scrollFraction != coordinator.lastScrollFraction {
            coordinator.lastScrollFraction = scrollFraction
            coordinator.scroll(to: scrollFraction)
        }
    }

    struct PreviewStyle: Equatable {
        var font: PreviewFont
        var size: Double
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var hasLoaded = false
        var loadedBase: URL?
        var loadedStyle: PreviewStyle?
        var lastScrollFraction: Double?
        private var isReady = false
        private var pendingHTML: String?
        private var renderedHTML: String?
        private var pendingScroll: Double?
        private var lastMarkdown: String?

        func update(markdown: String) {
            guard markdown != lastMarkdown else { return }
            lastMarkdown = markdown
            render(MarkdownRenderer.html(from: markdown))
        }

        func load(base: URL?, style: PreviewStyle) {
            hasLoaded = true
            loadedBase = base
            loadedStyle = style
            isReady = false
            lastScrollFraction = nil  // Re-apply the editor's scroll position to the new page.
            pendingHTML = pendingHTML ?? renderedHTML
            renderedHTML = nil
            let baseURL = base.map { LocalFileSchemeHandler.url(forDirectory: $0) }
            webView?.loadHTMLString(PreviewTemplate.page(style: style), baseURL: baseURL)
        }

        func render(_ html: String) {
            guard html != renderedHTML else { return }
            guard isReady, let webView else {
                pendingHTML = html
                return
            }
            renderedHTML = html
            webView.callAsyncJavaScript("document.getElementById('content').innerHTML = html", arguments: ["html": html], in: nil, in: .page) { _ in }
        }

        func scroll(to fraction: Double) {
            guard isReady, let webView else {
                pendingScroll = fraction
                return
            }
            webView.callAsyncJavaScript(
                "window.scrollTo(0, Math.max(0, (document.documentElement.scrollHeight - window.innerHeight) * f))", arguments: ["f": fraction], in: nil, in: .page) { _ in }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            if let html = pendingHTML {
                pendingHTML = nil
                render(html)
            }
            if let fraction = pendingScroll {
                pendingScroll = nil
                scroll(to: fraction)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            guard url.scheme?.lowercased() != "javascript" else { return }

            if url.scheme == LocalFileSchemeHandler.scheme || url.scheme == "about" {
                if let fragment = url.fragment, url.path.hasSuffix("/") || url.path.isEmpty {
                    // In-page anchor such as a table-of-contents link.
                    webView.callAsyncJavaScript(
                        "document.getElementById(decodeURIComponent(id))?.scrollIntoView({ behavior: 'smooth' })", arguments: ["id": fragment], in: nil, in: .page) { _ in }
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: url.path(percentEncoded: false)))
                }
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// Serves files next to the document (e.g. relative image paths) to the preview.
@MainActor
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "macdown-file"

    static func url(forDirectory directory: URL) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = ""
        components.path = directory.path(percentEncoded: false).hasSuffix("/")
            ? directory.path(percentEncoded: false)
            : directory.path(percentEncoded: false) + "/"
        return components.url ?? directory
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let fileURL = URL(fileURLWithPath: url.path(percentEncoded: false))
        guard let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

enum PreviewTemplate {
    static func page(style: PreviewView.PreviewStyle) -> String {
        let family = style.font == .serif
            ? #"ui-serif, "New York", Georgia, serif"#
            : #"-apple-system, system-ui, "Helvetica Neue", sans-serif"#
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <style>
        :root {
          color-scheme: light dark;
          --text: #1d1d1f;
          --secondary: #6e6e73;
          --background: #ffffff;
          --rule: rgba(0, 0, 0, 0.1);
          --code-bg: rgba(0, 0, 0, 0.045);
          --code-text: #c41a5b;
          --accent: -apple-system-control-accent;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --text: #f5f5f7;
            --secondary: #a1a1a6;
            --background: #1e1e1e;
            --rule: rgba(255, 255, 255, 0.12);
            --code-bg: rgba(255, 255, 255, 0.07);
            --code-text: #ff7ab2;
          }
        }
        html { background: var(--background); }
        body {
          font-family: \(family);
          font-size: \(Int(style.size))px;
          line-height: 1.6;
          color: var(--text);
          background: var(--background);
          max-width: 46em;
          margin: 0 auto;
          padding: 24px 32px 64px;
          -webkit-font-smoothing: antialiased;
          word-wrap: break-word;
        }
        ::selection { background: -apple-system-selected-text-background; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.6em 0 0.6em; font-weight: 650; }
        h1 { font-size: 2em; font-weight: 700; }
        h2 { font-size: 1.5em; }
        h1, h2 { padding-bottom: 0.3em; border-bottom: 1px solid var(--rule); }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1em; }
        h5, h6 { font-size: 0.875em; color: var(--secondary); }
        body > :first-child { margin-top: 0; }
        p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
        a { color: #0a66d6; color: var(--accent); text-decoration: none; }
        a:hover { text-decoration: underline; }
        ul, ol { padding-left: 1.6em; }
        li + li { margin-top: 0.25em; }
        li.task { list-style: none; margin-left: -1.4em; }
        li.task input { margin: 0 0.4em 0 0; vertical-align: -1px; accent-color: var(--accent); }
        blockquote { margin-left: 0; padding: 0 1em; color: var(--secondary); border-left: 3px solid var(--rule); }
        code, pre { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.875em; }
        code { background: var(--code-bg); color: var(--code-text); padding: 0.15em 0.35em; border-radius: 5px; }
        pre { background: var(--code-bg); padding: 0.9em 1.1em; border-radius: 8px; overflow-x: auto; line-height: 1.45; }
        pre code { background: none; color: inherit; padding: 0; font-size: 1em; }
        hr { border: none; border-top: 1px solid var(--rule); margin: 2em 0; }
        img { max-width: 100%; border-radius: 6px; }
        table { border-collapse: collapse; display: block; overflow-x: auto; }
        th, td { border: 1px solid var(--rule); padding: 0.4em 0.8em; }
        th { font-weight: 600; background: var(--code-bg); }
        del { color: var(--secondary); }
        </style>
        </head>
        <body><article id="content"></article></body>
        </html>
        """
    }
}
