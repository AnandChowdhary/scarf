import Foundation

/// Host-side sliding-window rate limit for mini-app bridge calls that
/// drive real work — chiefly `scarf.prompt`, which forwards web-supplied
/// text to a tool-enabled Hermes agent. Caps runaway loops (an
/// agent-generated mini-app that prompts in a tight cycle) without a timer:
/// the decision is a pure function of the prior call timestamps + now, so
/// it's deterministic and unit-testable. The owning actor holds the
/// `history` and feeds `Date()`.
public struct MiniAppRateLimiter: Sendable {
    public let maxEvents: Int
    public let windowSeconds: TimeInterval

    public init(maxEvents: Int = 8, windowSeconds: TimeInterval = 60) {
        self.maxEvents = max(1, maxEvents)
        self.windowSeconds = max(0.001, windowSeconds)
    }

    /// Decide whether a call at `now` is allowed given `history`, and
    /// return the history to carry forward. Pure: drops timestamps older
    /// than the window, allows when the remaining count is under `max`
    /// (appending `now`), denies otherwise (history unchanged but pruned).
    public func decide(now: Date, history: [Date]) -> (allowed: Bool, history: [Date]) {
        let cutoff = now.addingTimeInterval(-windowSeconds)
        let recent = history.filter { $0 > cutoff }
        if recent.count < maxEvents {
            return (true, recent + [now])
        }
        return (false, recent)
    }
}
