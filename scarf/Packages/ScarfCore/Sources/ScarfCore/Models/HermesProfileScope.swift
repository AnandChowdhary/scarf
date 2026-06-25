import Foundation

/// Pure resolution of a *selected* Hermes profile to the effective
/// `HERMES_HOME` directory, for ScarfGo's per-connection profile scoping
/// (issue #120, "Design B").
///
/// Unlike `HermesProfileResolver` — which reads the LOCAL
/// `~/.hermes/active_profile` for the Mac app and performs filesystem I/O
/// — this type does **no** I/O. It maps a `(base home, selected profile
/// name)` pair to a path string, so it works for remote homes reached over
/// SSH (where there is no local `active_profile` to read) and is trivially
/// testable on any platform.
///
/// **Design B.** ScarfGo points its own reads/writes/CLI at a chosen
/// profile WITHOUT mutating the host's `active_profile`:
/// - File layer: `resolveHome` becomes the `remoteHome` override, so every
///   `HermesPathSet` path (state.db, memories, cron, sessions, …) follows.
/// - Process layer: the (normalized) name is passed to `hermes -p <name>`.
///
/// Hermes treats a missing/empty/`"default"` selection as the root home,
/// and lays named profiles out at `<root>/profiles/<name>` for both
/// standard (`~/.hermes/profiles/x`) and Docker (`/opt/data/profiles/x`)
/// roots. See the memory note "Hermes profile / HERMES_HOME resolution
/// (source-verified v0.16)".
public enum HermesProfileScope {

    /// The sentinel name for the default (root) profile.
    public static let defaultProfileName = "default"

    /// Hermes's own profile-id validation, mirrored from
    /// `hermes_cli/profiles.py` (`^[a-z0-9][a-z0-9_-]{0,63}$`). Mirrored
    /// here so we never build a filesystem path or a `-p` argument from a
    /// malformed name — the regex rejects `/`, `.`, whitespace, and shell
    /// metacharacters, which is also our path-injection guard.
    private static let nameRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9_-]{0,63}$")
    }()

    /// Whether `name` is a syntactically valid Hermes profile id.
    public static func isValidName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return nameRegex.firstMatch(in: name, range: range) != nil
    }

    /// Normalize a raw selection to either a valid named profile or `nil`
    /// (meaning "default / root home"). Whitespace is trimmed; empty,
    /// `"default"`, and invalid names all normalize to `nil` — the
    /// fail-safe that keeps ScarfGo on the root home rather than a bogus
    /// path or argument.
    public static func normalize(_ selection: String?) -> String? {
        guard let raw = selection?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw != defaultProfileName,
              isValidName(raw)
        else { return nil }
        return raw
    }

    /// Effective Hermes home for a selected profile.
    ///
    /// - Parameters:
    ///   - baseHome: the ROOT hermes home for the host — the value ScarfGo
    ///     uses with no profile selected (e.g. `"~/.hermes"` unexpanded,
    ///     which the remote shell resolves, or a custom `"/opt/data"`).
    ///     Trailing slashes are trimmed.
    ///   - profile: the selected profile name. `nil`/empty/`"default"`/
    ///     invalid → returns `baseHome` unchanged (default profile).
    /// - Returns: `baseHome` for the default profile, else
    ///   `"<baseHome>/profiles/<name>"`.
    public static func resolveHome(baseHome: String, profile: String?) -> String {
        let base = trimmedBase(baseHome)
        guard let name = normalize(profile) else { return base }
        return base + "/profiles/" + name
    }

    /// Trim trailing slashes from a base home, preserving a lone `"/"`.
    private static func trimmedBase(_ s: String) -> String {
        var base = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.count > 1 && base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }
}
