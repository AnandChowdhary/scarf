# Clawdia App Intents

## Goal

Expose Clawdia through Siri, Shortcuts, Spotlight, and the Action button with four useful system entry points:

- Start a voice-first conversation with Clawdia.
- Continue the most recently active Hermes session.
- Start a voice-first conversation scoped to a named project.
- Capture a dictated idea by sending it to Hermes.

## Design

1. Define four `AppIntent` types and publish them from one `AppShortcutsProvider` with natural invocation phrases and recognizable symbols.
2. Persist each invocation as a small `Codable` request before opening the app. This keeps cold launches reliable even though the server and Chat coordinator do not exist when Siri first runs the intent.
3. Attach a main-actor router when the connected tab hierarchy appears. The router delivers the request to Chat and clears persistent storage only after Chat consumes it.
4. If exactly one server is configured, connect it automatically for a pending system entry. With multiple servers, keep the request queued while the user chooses the intended server.
5. Reuse the existing chat/session/project/Drive Mode paths rather than creating a parallel conversation implementation.

## Behavior

- **Start conversation:** starts a fresh session and enters Drive Mode when Realtime credentials are available.
- **Continue last session:** resumes the Hermes session with the most recent message activity, falling back to a new session when no prior session exists.
- **Talk about project:** case-insensitively resolves a registered project by name (then by unique partial match), starts its project-scoped chat, and enters Drive Mode.
- **Capture idea:** starts a fresh Hermes session and sends `Capture this idea: …` immediately.

## Verification

- Unit-test persistence, stale-request handling, project-name resolution, and request routing.
- Build the iOS target for the simulator so App Intents metadata extraction is exercised.
- Confirm the four shortcuts appear in the Shortcuts app; Siri/Spotlight/Action-button discovery requires an installed build and is a device verification step.
