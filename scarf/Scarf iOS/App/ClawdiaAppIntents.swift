import AppIntents
import Foundation
import ScarfCore

/// A durable handoff from an App Intent into the connected Chat surface.
/// Siri can run an intent before SwiftUI has constructed RootModel (and long
/// before a server-specific ScarfGoCoordinator exists), so the intent writes
/// this value first and Chat clears it only after consuming the request.
nonisolated struct ClawdiaSystemEntryRequest: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case startConversation
        case continueLastSession
        case projectConversation
        case captureIdea
    }

    let id: UUID
    let kind: Kind
    let value: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        value: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
    }
}

nonisolated enum ClawdiaSystemEntryStore {
    static let key = "so.sycamore.clawdia.pending-system-entry"
    static let maximumAge: TimeInterval = 60 * 60

    static func save(
        _ request: ClawdiaSystemEntryRequest,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        defaults.set(data, forKey: key)
    }

    static func pendingRequest(
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> ClawdiaSystemEntryRequest? {
        guard let data = defaults.data(forKey: key),
              let request = try? JSONDecoder().decode(ClawdiaSystemEntryRequest.self, from: data)
        else {
            defaults.removeObject(forKey: key)
            return nil
        }
        guard now.timeIntervalSince(request.createdAt) <= maximumAge else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return request
    }

    static func clear(
        id: UUID,
        defaults: UserDefaults = .standard
    ) {
        guard pendingRequest(defaults: defaults)?.id == id else { return }
        defaults.removeObject(forKey: key)
    }
}

/// Pure name resolution so Siri's free-form project parameter remains
/// predictable and independently testable. Prefer an exact name, then an
/// exact final path component, then accept a partial name only when unique.
nonisolated enum ClawdiaProjectResolver {
    nonisolated static func resolve(named rawName: String, in projects: [ProjectEntry]) -> ProjectEntry? {
        let name = normalized(rawName)
        guard !name.isEmpty else { return nil }
        let visible = projects.filter { !$0.archived }

        if let exact = visible.first(where: { normalized($0.name) == name }) {
            return exact
        }
        if let pathMatch = visible.first(where: {
            normalized(($0.path as NSString).lastPathComponent) == name
        }) {
            return pathMatch
        }

        let partial = visible.filter {
            normalized($0.name).contains(name) || name.contains(normalized($0.name))
        }
        return partial.count == 1 ? partial[0] : nil
    }

    nonisolated private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

@MainActor
final class ClawdiaSystemEntryRouter {
    static let shared = ClawdiaSystemEntryRouter()

    weak var rootModel: RootModel?
    weak var coordinator: ScarfGoCoordinator?

    func attach(rootModel: RootModel) {
        self.rootModel = rootModel
        routePendingRequest()
    }

    func attach(coordinator: ScarfGoCoordinator) {
        self.coordinator = coordinator
        routePendingRequest()
    }

    func submit(_ request: ClawdiaSystemEntryRequest) {
        ClawdiaSystemEntryStore.save(request)
        routePendingRequest()
    }

    func complete(_ requestID: UUID) {
        ClawdiaSystemEntryStore.clear(id: requestID)
        if coordinator?.pendingSystemEntryRequest?.id == requestID {
            coordinator?.pendingSystemEntryRequest = nil
        }
    }

    func routePendingRequest() {
        guard let request = ClawdiaSystemEntryStore.pendingRequest() else { return }
        if let coordinator {
            coordinator.receiveSystemEntry(request)
        } else if let rootModel {
            Task { await rootModel.connectForPendingSystemEntryIfPossible() }
        }
    }
}

private protocol ClawdiaForegroundIntent: AppIntent {}

extension ClawdiaForegroundIntent {
    @available(iOS, introduced: 16.0, obsoleted: 26.0)
    static var openAppWhenRun: Bool { true }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    static func submit(_ request: ClawdiaSystemEntryRequest) {
        ClawdiaSystemEntryRouter.shared.submit(request)
    }
}

struct StartClawdiaConversationIntent: ClawdiaForegroundIntent {
    static let title: LocalizedStringResource = "Start a Clawdia Conversation"
    static let description = IntentDescription(
        "Start a new, hands-free conversation with Clawdia."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Self.submit(.init(kind: .startConversation))
        return .result(dialog: "Starting a conversation with Clawdia.")
    }
}

struct ContinueLastHermesSessionIntent: ClawdiaForegroundIntent {
    static let title: LocalizedStringResource = "Continue Last Clawdia Session"
    static let description = IntentDescription(
        "Open the Clawdia session you used most recently."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Self.submit(.init(kind: .continueLastSession))
        return .result(dialog: "Continuing your last Clawdia session.")
    }
}

struct ClawdiaProjectEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Project")
    static let defaultQuery = ClawdiaProjectEntityQuery()

    let id: String
    let name: String

    init(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = trimmed
        self.name = trimmed
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "folder.fill"))
    }
}

struct ClawdiaProjectEntityQuery: EntityStringQuery {
    nonisolated init() {}

    nonisolated func entities(for identifiers: [String]) async throws -> [ClawdiaProjectEntity] {
        identifiers.map(ClawdiaProjectEntity.init(name:))
    }

    nonisolated func suggestedEntities() async throws -> [ClawdiaProjectEntity] {
        ClawdiaProjectEntityCache.names().map(ClawdiaProjectEntity.init(name:))
    }

    nonisolated func entities(matching string: String) async throws -> [ClawdiaProjectEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return try await suggestedEntities() }
        let matches = ClawdiaProjectEntityCache.names().filter {
            $0.localizedCaseInsensitiveContains(query)
        }
        // EntityStringQuery may be invoked before Clawdia has cached its
        // remote registry. Preserve the spoken value so Chat can resolve it
        // against the live registry after the app opens.
        return (matches.isEmpty ? [query] : matches).map(ClawdiaProjectEntity.init(name:))
    }
}

nonisolated enum ClawdiaProjectEntityCache {
    private static let key = "so.sycamore.clawdia.app-intent-project-names"

    nonisolated static func save(_ projects: [ProjectEntry], defaults: UserDefaults = .standard) {
        defaults.set(
            projects.filter { !$0.archived }.map(\.name).sorted(),
            forKey: key
        )
    }

    nonisolated static func names(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }
}

struct StartProjectConversationIntent: ClawdiaForegroundIntent {
    static let title: LocalizedStringResource = "Talk About a Project"
    static let description = IntentDescription(
        "Start a hands-free conversation in one of your registered projects."
    )

    @Parameter(title: "Project")
    var project: ClawdiaProjectEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Talk about \(\.$project)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Self.submit(.init(kind: .projectConversation, value: project.name))
        return .result(dialog: "Opening the \(project.name) project in Clawdia.")
    }
}

struct CaptureIdeaIntent: ClawdiaForegroundIntent {
    static let title: LocalizedStringResource = "Capture an Idea"
    static let description = IntentDescription(
        "Send a dictated idea to Clawdia in a new session."
    )

    @Parameter(title: "Idea")
    var idea: String

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$idea)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Self.submit(.init(kind: .captureIdea, value: idea))
        return .result(dialog: "Capturing your idea with Clawdia.")
    }
}

struct ClawdiaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartClawdiaConversationIntent(),
            phrases: [
                "Start a conversation with \(.applicationName)",
                "Talk to \(.applicationName)"
            ],
            shortTitle: "Talk to Clawdia",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: ContinueLastHermesSessionIntent(),
            phrases: [
                "Continue my last Clawdia session in \(.applicationName)",
                "Continue my conversation with \(.applicationName)"
            ],
            shortTitle: "Continue Clawdia",
            systemImageName: "arrow.clockwise.circle.fill"
        )
        AppShortcut(
            intent: StartProjectConversationIntent(),
            phrases: [
                "Talk about the \(\.$project) project with \(.applicationName)",
                "Talk about \(\.$project) with \(.applicationName)"
            ],
            shortTitle: "Talk About Project",
            systemImageName: "folder.fill.badge.person.crop"
        )
        AppShortcut(
            intent: CaptureIdeaIntent(),
            phrases: [
                "Capture an idea with \(.applicationName)",
                "Save an idea in \(.applicationName)"
            ],
            shortTitle: "Capture Idea",
            systemImageName: "lightbulb.fill"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
