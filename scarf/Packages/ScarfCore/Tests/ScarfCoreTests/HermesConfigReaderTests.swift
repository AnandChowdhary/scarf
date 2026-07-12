import Testing
import Foundation
@testable import ScarfCore

/// Pure-parse tests for `HermesConfigReader.parseModelShowLine` — the
/// gh#112 in-container last resort that extracts model.default /
/// model.provider from `hermes config show`'s human-formatted output.
/// Samples mirror the real v0.17 box format (verified live 2026-07-12).
@Suite struct HermesConfigReaderTests {

    private static let v017Show = """

    ┌─────────────────────────────────────────────────────────┐
    │              ⚕ Hermes Configuration                    │
    └─────────────────────────────────────────────────────────┘

    ◆ Paths
      Config:       /root/.hermes/config.yaml

    ◆ Model
      Model:        {'default': 'claude-haiku-4-5-20251001', 'provider': 'anthropic'}
      Max turns:    60

    ◆ Display
      Personality:  kawaii
    """

    @Test func parsesRealV017Output() {
        let parsed = HermesConfigReader.parseModelShowLine(Self.v017Show)
        #expect(parsed?.default == "claude-haiku-4-5-20251001")
        #expect(parsed?.provider == "anthropic")
    }

    @Test func keyOrderDoesNotMatter() {
        let out = "  Model:  {'provider': 'openrouter', 'default': 'xiaomi/mimo-v2.5'}"
        let parsed = HermesConfigReader.parseModelShowLine(out)
        #expect(parsed?.default == "xiaomi/mimo-v2.5")
        #expect(parsed?.provider == "openrouter")
    }

    @Test func handlesDoubleQuotedReprValues() {
        // Python repr flips to double quotes when a value contains a
        // single quote.
        let out = "  Model:  {\"default\": \"it's-a-model\", 'provider': 'custom:x'}"
        let parsed = HermesConfigReader.parseModelShowLine(out)
        #expect(parsed?.provider == "custom:x")
    }

    @Test func missingModelLineReturnsNil() {
        #expect(HermesConfigReader.parseModelShowLine("◆ Paths\n  Config: /x/y.yaml") == nil)
    }

    @Test func modelLineWithoutDictReturnsNil() {
        #expect(HermesConfigReader.parseModelShowLine("  Model:        (not set)") == nil)
    }

    @Test func synthesizedConfigPassesModelPreflight() {
        // The probe's whole point: a synthesized minimal config must
        // satisfy the same gate the full YAML satisfies.
        guard let parsed = HermesConfigReader.parseModelShowLine(Self.v017Show),
              let d = parsed.default, let p = parsed.provider else {
            Issue.record("parse failed")
            return
        }
        let config = HermesConfig(yaml: "model:\n  default: \(d)\n  provider: \(p)\n")
        #expect(ModelPreflight.check(config).isConfigured)
    }
}
