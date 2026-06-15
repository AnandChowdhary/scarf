import Foundation

/// Pure, WebKit-free core of the `scarf-miniapp://` asset server: resolve a
/// requested path to a file **inside** one mini-app's directory, reject any
/// escape, and decide the response's MIME type + CSP.
///
/// Kept out of the WebKit layer precisely so the security-critical
/// containment check is unit-testable without a `WKWebView`. The Mac-target
/// `MiniAppSchemeHandler` is a thin shell over this.
///
/// **Why a custom scheme + this resolver, not `file://`.** Serving the
/// mini-app over a directory-scoped custom scheme means web content gets a
/// stable origin (`scarf-miniapp://…`) with no path-traversal into the rest
/// of the filesystem — `file://` would let `../../` walk out. Every request
/// is resolved here and bounded to the mini-app's own directory.
public enum MiniAppAssetResolver {

    /// The custom URL scheme mini-apps are served over.
    public static let scheme = "scarf-miniapp"

    /// Fixed authority component of mini-app URLs (`scarf-miniapp://app/…`).
    /// Arbitrary + ignored during resolution — only the path matters.
    public static let host = "app"

    /// Strict default Content-Security-Policy for the served document.
    ///
    /// `connect-src 'none'` blocks all network (no exfiltration) until the
    /// `net` permission ships an allowlist; `default-src 'none'` denies
    /// everything not explicitly re-allowed; `'unsafe-inline'` for
    /// script/style is the deliberate v1 concession so build-step-free
    /// mini-apps run their own bundled code — the trust boundary is the
    /// blocked network + the directory-scoped scheme, not script provenance.
    public static let contentSecurityPolicy =
        "default-src 'none'; "
        + "script-src 'self' 'unsafe-inline'; "
        + "style-src 'self' 'unsafe-inline'; "
        + "img-src 'self' data:; "
        + "font-src 'self' data:; "
        + "media-src 'self'; "
        + "connect-src 'none'; "
        + "base-uri 'none'; "
        + "form-action 'none'; "
        + "frame-ancestors 'none'"

    /// Resolve a request path (`url.path`, already percent-decoded) to an
    /// absolute file path strictly inside `baseDirectory`. Returns `nil`
    /// when the path is empty, names the directory itself, or escapes the
    /// base (`..`, absolute re-root, `~` expansion). The returned path is
    /// normalized but NOT existence-checked — the caller reads it and 404s
    /// on miss.
    public static func resolvedPath(requestPath: String, baseDirectory: String) -> String? {
        let base = (baseDirectory as NSString).standardizingPath
        guard !base.isEmpty else { return nil }

        var rel = requestPath
        while rel.hasPrefix("/") { rel.removeFirst() }
        rel = rel.trimmingCharacters(in: .whitespaces)
        guard !rel.isEmpty else { return nil }
        // Reject control characters / NUL outright.
        guard !rel.unicodeScalars.contains(where: { $0.value < 0x20 }) else { return nil }

        let joined = base + "/" + rel
        let normalized = (joined as NSString).standardizingPath

        // Containment: the resolved path must sit strictly below base/.
        // (Equal-to-base means they asked for the directory, not a file.)
        guard normalized.hasPrefix(base + "/") else { return nil }
        return normalized
    }

    /// MIME type for a file path, by extension. Unknown → octet-stream.
    public static func mimeType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "map": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "wasm": return "application/wasm"
        case "txt", "md": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }

    /// Build the entry URL string for a mini-app's entry document.
    public static func entryURLString(entry: String) -> String {
        var e = entry
        while e.hasPrefix("/") { e.removeFirst() }
        if e.isEmpty { e = "index.html" }
        return "\(scheme)://\(host)/\(e)"
    }
}
