# Clawdia iOS Language Pass

## Goal

Make Clawdia the sole user-facing agent name throughout the iOS app. Status messages, chat hints, onboarding, shortcuts, settings, permissions, error copy, and accessibility labels should not address the user as if they were talking to a separate product named Hermes.

## Scope

1. Replace conversational and branded uses of “Hermes” with “Clawdia” in iOS string literals.
2. Use “Clawdia agent” where the text describes the remote runtime or host rather than the app itself.
3. Preserve real implementation names and commands—Swift types, methods, protocol fields, logs, `hermes` CLI examples, `.hermes` paths, capability/version identifiers, and technical documentation that must remain accurate.
4. Update App Intent titles, dialogs, phrases, and tiles so Siri, Shortcuts, Spotlight, and the Action button expose Clawdia terminology only.
5. Update tests and the iOS user-facing wiki section, then verify the simulator build, App Intents metadata, and iOS test suite.
