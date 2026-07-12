# Clawdia orange and single-server launch

## Goal

Make Clawdia's iOS controls visually match the current app icon and remove an unnecessary launch choice when the user has only one usable server.

## Design

1. Add icon-derived, light/dark Clawdia orange tokens to ScarfDesign and route the semantic accent aliases to them on iOS only. Keep the existing Scarf rust tokens on macOS.
2. Update the iOS app target's AccentColor asset to the same icon-derived colors for system-owned accent surfaces.
3. During root-state loading, auto-connect when exactly one server has both configuration and a stored SSH key. Continue showing the server list for multiple servers or an incomplete single-server entry.
4. Add focused root-state tests covering the one-server, multiple-server, and missing-key cases.
5. Update the wiki with the launch behavior and platform-specific accent distinction.

## Verification

- Completed: all 20 iOS unit tests, including the three root-routing cases.
- Completed: ScarfDesign macOS build and Clawdia Release simulator build.
- Completed: runtime accent screenshot, asset JSON validation, final diff inspection, and `git diff --check`.
