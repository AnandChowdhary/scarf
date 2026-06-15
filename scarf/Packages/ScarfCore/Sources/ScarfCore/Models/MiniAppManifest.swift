import Foundation

/// On-disk manifest for a mini-app — `miniapp.json` at the root of a
/// mini-app directory (`<project>/.scarf/miniapps/<id>/`).
///
/// A mini-app is a small web surface (HTML/CSS/JS) rendered inside Scarf
/// over a narrow, versioned JS bridge (`window.scarf`). It is a project
/// facet: shipped via `.scarftemplate`, dropped into the project, or
/// generated on the fly by the agent. See the Mini-App Bridge Contract.
///
/// ```json
/// { "id": "kanban-burndown", "name": "Burndown", "version": "1.0.0",
///   "entry": "index.html", "minBridgeVersion": "1.0",
///   "permissions": ["query:kanban.tasks", "prompt", "events", "store"],
///   "panelHint": { "preferredWidth": 420, "placement": "panel" },
///   "generated": false }
/// ```
///
/// Decoding is lenient: only `id` + `name` are required; `entry` defaults
/// to `index.html`, `permissions` to `[]` (default-deny), `generated` to
/// `false`, `minBridgeVersion` to `"1.0"`. Unknown keys are ignored so the
/// format can grow without invalidating existing manifests.
public struct MiniAppManifest: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var version: String
    /// Relative entry document inside the mini-app dir.
    public var entry: String
    /// Minimum `window.scarf` bridge version the mini-app needs; checked at
    /// mount (`scarf.version`). Mismatch → host loads degraded or refuses.
    public var minBridgeVersion: String
    /// Declared bridge surfaces (default-deny — see `MiniAppPermission`).
    public var permissions: [MiniAppPermission]
    public var panelHint: PanelHint?
    /// `true` for agent-written mini-apps — stricter permission defaults
    /// (no `net`, no `file:write`) until the user explicitly elevates.
    public var generated: Bool

    /// Layout hint for the cockpit panel host. Advisory only.
    public struct PanelHint: Codable, Sendable, Hashable {
        public var preferredWidth: Double?
        public var placement: String?

        public init(preferredWidth: Double? = nil, placement: String? = nil) {
            self.preferredWidth = preferredWidth
            self.placement = placement
        }
    }

    public init(
        id: String,
        name: String,
        version: String = "1.0.0",
        entry: String = "index.html",
        minBridgeVersion: String = "1.0",
        permissions: [MiniAppPermission] = [],
        panelHint: PanelHint? = nil,
        generated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.entry = entry
        self.minBridgeVersion = minBridgeVersion
        self.permissions = permissions
        self.panelHint = panelHint
        self.generated = generated
    }

    // MARK: - Codable (lenient)

    private enum CodingKeys: String, CodingKey {
        case id, name, version, entry, minBridgeVersion, permissions, panelHint, generated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.version = try c.decodeIfPresent(String.self, forKey: .version) ?? "1.0.0"
        self.entry = try c.decodeIfPresent(String.self, forKey: .entry) ?? "index.html"
        self.minBridgeVersion = try c.decodeIfPresent(String.self, forKey: .minBridgeVersion) ?? "1.0"
        self.permissions = try c.decodeIfPresent([MiniAppPermission].self, forKey: .permissions) ?? []
        self.panelHint = try c.decodeIfPresent(PanelHint.self, forKey: .panelHint)
        self.generated = try c.decodeIfPresent(Bool.self, forKey: .generated) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(version, forKey: .version)
        try c.encode(entry, forKey: .entry)
        try c.encode(minBridgeVersion, forKey: .minBridgeVersion)
        try c.encode(permissions, forKey: .permissions)
        try c.encodeIfPresent(panelHint, forKey: .panelHint)
        try c.encode(generated, forKey: .generated)
    }
}
