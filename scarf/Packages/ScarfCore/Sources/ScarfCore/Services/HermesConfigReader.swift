import Foundation

/// Transport-aware reads of the raw `config.yaml` with Hermes-CLI
/// fallbacks for hosts where the file isn't where Scarf expects it —
/// a HERMES_HOME override, or a `hermes` wrapper that runs the CLI
/// inside a container so the file never exists on the host at all
/// (gh#112: Docker-hosted Hermes).
///
/// Read order:
///  1. Direct file read at `paths.configYAML` (SFTP on iOS remotes,
///     ssh `cat` on macOS remotes, plain file locally).
///  2. `cat "$(hermes config path)"` in ONE remote shell — the wrapper
///     resolves the real path (HERMES_HOME, profile) and the `cat`
///     runs beside it, so a host-side wrapper with a nonstandard home
///     works. Also covers containers whose Hermes home is bind-mounted
///     onto the host at the path `config path` reports.
///  3. (`probeModelConfig` only) `hermes config show` — the one read
///     that runs wherever the CLI runs, including inside a container.
///     Yields just `model.default` + `model.provider`, enough for the
///     chat preflight gate; full Settings still need a file the
///     transport can see.
///
/// All entry points do blocking transport I/O — call off the MainActor.
public enum HermesConfigReader {
    /// Same PATH prelude the write path uses (`IOSSettingsViewModel
    /// .saveValue`, the iOS chat preflight's `config set`) so remote
    /// non-interactive shells find `hermes` even when it lives in
    /// `~/.local/bin` or `/opt/homebrew/bin`.
    public static let pathPrelude =
        "PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.hermes/bin:$PATH\""

    /// Steps 1 + 2. Nil when the file is invisible to both the transport
    /// and the host shell (pure in-container Hermes, or no Hermes at all).
    public static func readRawConfig(context: ServerContext) -> String? {
        if let direct = context.readText(context.paths.configYAML) { return direct }
        return readViaConfigPath(context: context)
    }

    /// Step 2 on its own. Nil when the CLI is missing, the path doesn't
    /// resolve, or the resolved file isn't readable from the host shell.
    /// Remote-only: the wrapper/container topologies this exists for are
    /// remote-host shapes, and a local "file missing" should stay missing
    /// rather than consult whatever `hermes` happens to be on this Mac's
    /// PATH.
    static func readViaConfigPath(context: ServerContext) -> String? {
        guard context.isRemote else { return nil }
        let hermes = context.paths.hermesBinary
        let script = "\(pathPrelude); p=\"$(\(hermes) config path 2>/dev/null)\" && [ -n \"$p\" ] && cat \"$p\""
        guard let result = try? context.makeTransport().runProcess(
            executable: "/bin/sh",
            args: ["-c", script],
            stdin: nil,
            timeout: 15
        ), result.exitCode == 0 else { return nil }
        let yaml = result.stdoutString
        return yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : yaml
    }

    /// Step 3 — the in-container last resort. Non-nil means the Hermes
    /// CLI answered even though the config file is invisible, which is
    /// the signature of a containerized install; callers use that to
    /// pick topology-specific guidance. The synthesized config carries
    /// only the model section.
    public static func probeModelConfig(context: ServerContext) -> HermesConfig? {
        guard context.isRemote else { return nil }
        let hermes = context.paths.hermesBinary
        let script = "\(pathPrelude); \(hermes) config show 2>/dev/null"
        guard let result = try? context.makeTransport().runProcess(
            executable: "/bin/sh",
            args: ["-c", script],
            stdin: nil,
            timeout: 15
        ), result.exitCode == 0 else { return nil }
        guard let model = parseModelShowLine(result.stdoutString) else { return nil }
        var yaml = "model:\n"
        if let d = model.default { yaml += "  default: \(d)\n" }
        if let p = model.provider { yaml += "  provider: \(p)\n" }
        return HermesConfig(yaml: yaml)
    }

    /// Extract `default` / `provider` from `hermes config show`'s Model
    /// line, a Python-dict repr on v0.16–v0.18:
    ///
    ///     Model:        {'default': 'claude-haiku-4-5', 'provider': 'anthropic'}
    ///
    /// Key order varies and Python flips to double quotes when a value
    /// contains a single quote, so match per-key with either quote style.
    /// Nil when no Model line (or neither key) is present — treat as
    /// "CLI didn't answer usefully".
    static func parseModelShowLine(_ output: String) -> (default: String?, provider: String?)? {
        guard let line = output.split(separator: "\n").first(where: {
            $0.contains("Model:") && $0.contains("{")
        }) else { return nil }
        func value(forKey key: String) -> String? {
            guard let regex = try? Regex("['\"]\(key)['\"]:\\s*['\"]([^'\"]*)['\"]"),
                  let match = try? regex.firstMatch(in: String(line)),
                  match.output.count > 1,
                  let captured = match.output[1].substring
            else { return nil }
            let v = String(captured)
            return v.isEmpty ? nil : v
        }
        let d = value(forKey: "default")
        let p = value(forKey: "provider")
        guard d != nil || p != nil else { return nil }
        return (default: d, provider: p)
    }
}
