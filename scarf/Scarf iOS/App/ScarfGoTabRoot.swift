import SwiftUI
import UIKit
import ScarfCore
import ScarfIOS
import ScarfDesign

/// Clawdia's primary navigation surface. Text and Voice are separate
/// destinations backed by one shared Hermes conversation:
///
///     Dashboard | Text | Voice | Skills | System
///
/// Voice occupies the center position for thumb reach. Projects remains
/// available through System and contextual chat project selection, but no
/// longer competes with the two core conversation modes in the tab bar.
/// We stay on Apple's native `TabView`; `.sidebarAdaptable` continues to
/// provide the system's larger-device navigation treatment for free.
///
/// Each tab wraps its feature view in its own `NavigationStack` so push
/// navigation (Cron editor, Memory detail, Project detail, etc.) stays
/// scoped to the tab instead of bleeding across.
struct ScarfGoTabRoot: View {
    let serverID: ServerID
    let config: IOSServerConfig
    let key: SSHKeyBundle
    let onSoftDisconnect: @MainActor @Sendable () async -> Void
    let onForget: @MainActor @Sendable () async -> Void

    /// Stable per-tab context UUID — used for the System tab's Curator
    /// row so its CuratorViewModel reuses the cached SSH connection
    /// keyed by this id rather than building a fresh one. Same pattern
    /// as `sharedContextID` on ChatView.
    static let systemTabContextID: ServerID = ServerID(
        uuidString: "00000000-0000-0000-0000-0000000000A2"
    )!

    /// One coordinator per server-connected session. Cross-tab
    /// signalling (Dashboard row → Text resume, Project Detail
    /// → in-project Text handoff, notification deep-link → Text) flows
    /// through here. Also owns the selected Hermes profile (#120).
    @State private var coordinator: ScarfGoCoordinator

    /// Hermes version + capability flags for this remote. Drives the
    /// iOS version banner (v0.11 hosts get a yellow "update for new
    /// features" banner) and capability-gated affordances like ACP
    /// image attachments. Constructed once per server connection so
    /// the detection runs over the active SSH transport.
    @State private var capabilities: HermesCapabilitiesStore

    init(
        serverID: ServerID,
        config: IOSServerConfig,
        key: SSHKeyBundle,
        onSoftDisconnect: @escaping @MainActor @Sendable () async -> Void,
        onForget: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.serverID = serverID
        self.config = config
        self.key = key
        self.onSoftDisconnect = onSoftDisconnect
        self.onForget = onForget
        // Capability detection is host-level (Hermes version), so it runs
        // against the base context regardless of the selected profile.
        let ctx = config.toServerContext(id: serverID)
        _capabilities = State(initialValue: HermesCapabilitiesStore(context: ctx))
        // Coordinator owns the per-server profile selection (#120); it
        // loads any persisted choice from the store on construction.
        _coordinator = State(initialValue: ScarfGoCoordinator(serverID: serverID))
    }

    /// `config` with `remoteHome` re-pointed at the selected profile's
    /// directory (#120, Design B). Default selection leaves the base home
    /// untouched. Threaded to every feature view so all direct-file/DB
    /// reads and writes follow the profile through `HermesPathSet` —
    /// without mutating the host's `active_profile`.
    private var effectiveConfig: IOSServerConfig {
        var resolved = config
        resolved.remoteHome = HermesProfileScope.resolveHome(
            baseHome: config.remoteHome ?? HermesPathSet.defaultRemoteHome,
            profile: coordinator.selectedProfile
        )
        return resolved
    }

    /// SwiftUI's `.onChange(of: ScenePhase)` modifier on a non-active
    /// tab doesn't fire while the tab is unmounted — the coordinator
    /// is the single source of truth for scene-phase transitions
    /// across all tabs.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        profileScopedTabs
            .onAppear {
                // Give the notification router a handle to this session's
                // coordinator so notification-taps can route across tabs.
                // Weak ref — coordinator owns its own lifetime, router
                // just observes.
                NotificationRouter.shared.coordinator = coordinator
                ClawdiaSystemEntryRouter.shared.attach(coordinator: coordinator)
                let context = effectiveConfig.toServerContext(id: serverID)
                Task.detached {
                    let projects = ProjectDashboardService(context: context).loadRegistry().projects
                    ClawdiaProjectEntityCache.save(projects)
                }
                updateIdleTimer()
            }
            // Funnel scene-phase transitions through the coordinator so
            // tab view-models (notably ChatController) can react even
            // when their tab isn't currently on-screen.
            .onChange(of: scenePhase) { _, newPhase in
                coordinator.setScenePhase(newPhase)
                updateIdleTimer()
            }
            .onChange(of: coordinator.selectedTab) { _, _ in
                updateIdleTimer()
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active
            && coordinator.selectedTab == .voice
    }

    /// The 5-tab tree, re-identified by the selected profile so a switch
    /// fully rebuilds it (and every feature view-model) against the new
    /// profile's HERMES_HOME (#120) — the scoped, no-relaunch analogue of
    /// the Mac app's switch-and-relaunch. `body` wraps this with
    /// `.onAppear`/`.onChange` from the stable outer position, so those
    /// don't re-fire on a switch.
    private var profileScopedTabs: some View {
        // The transport factory is keyed by ServerID, so the correct
        // Keychain slot + config is picked automatically. Reuses the
        // server's own id as the context id so the CitadelServerTransport
        // pool caches per-server (instead of the singleton we had
        // pre-M9). Two active servers → two connection holders, no
        // SSH channel contention.
        let cfg = effectiveConfig
        let ctx = cfg.toServerContext(id: serverID)
        return ProfileScopedTabs(
            config: cfg,
            key: key,
            coordinator: coordinator,
            onSoftDisconnect: onSoftDisconnect,
            onForget: onForget
        )
        // Rebuild the whole tab subtree when the selected profile changes
        // so every feature view (and its view-model) reconstructs against
        // the new profile's HERMES_HOME (#120). This includes the shared
        // Text/Voice chat controller.
        .id(coordinator.selectedProfile ?? HermesProfileScope.defaultProfileName)
        .environment(\.serverContext, ctx)
        .environment(\.scarfGoCoordinator, coordinator)
        .environment(capabilities)
        .hermesCapabilities(capabilities)
    }
}

/// Owns the profile-scoped tab models. Text and Voice receive the same
/// controller instances so changing presentation never creates a second
/// ACP session or loses the transcript currently on screen.
private struct ProfileScopedTabs: View {
    let config: IOSServerConfig
    let key: SSHKeyBundle
    let coordinator: ScarfGoCoordinator
    let onSoftDisconnect: @MainActor @Sendable () async -> Void
    let onForget: @MainActor @Sendable () async -> Void

    @State private var chatController: ChatController
    @State private var voiceController: IOSRealtimeVoiceController

    init(
        config: IOSServerConfig,
        key: SSHKeyBundle,
        coordinator: ScarfGoCoordinator,
        onSoftDisconnect: @escaping @MainActor @Sendable () async -> Void,
        onForget: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.config = config
        self.key = key
        self.coordinator = coordinator
        self.onSoftDisconnect = onSoftDisconnect
        self.onForget = onForget
        let context = config.toServerContext(id: ChatView.sharedContextID)
        _chatController = State(initialValue: ChatController(context: context))
        _voiceController = State(initialValue: IOSRealtimeVoiceController())
    }

    var body: some View {
        @Bindable var coordinator = coordinator
        TabView(selection: $coordinator.selectedTab) {
            // 1 — Dashboard: stats + recent sessions.
            NavigationStack {
                DashboardView(config: config, key: key, onSoftDisconnect: onSoftDisconnect)
            }
            .tabItem {
                Label("Dashboard", systemImage: "gauge.with.needle")
            }
            .tag(ScarfGoCoordinator.Tab.dashboard)
            .accessibilityLabel("Dashboard tab")

            // 2 — Text: full transcript plus the keyboard composer.
            NavigationStack {
                ChatView(
                    config: config,
                    key: key,
                    presentationMode: .text,
                    controller: chatController,
                    voiceController: voiceController
                )
            }
            .tabItem {
                Label("Text", systemImage: "text.bubble.fill")
            }
            .tag(ScarfGoCoordinator.Tab.text)
            .accessibilityLabel("Text tab")

            // 3 — Voice: the same transcript/session with the continuous,
            // background-capable voice composer. Centered for thumb reach.
            NavigationStack {
                ChatView(
                    config: config,
                    key: key,
                    presentationMode: .voice,
                    controller: chatController,
                    voiceController: voiceController
                )
            }
            .tabItem {
                Label("Voice", systemImage: "waveform")
            }
            .tag(ScarfGoCoordinator.Tab.voice)
            .accessibilityLabel("Voice tab")

            // 4 — Skills: Installed | Browse Hub | Updates, mirroring
            // the Mac app's 3-tab skills surface.
            NavigationStack {
                SkillsView(config: config)
            }
            .tabItem {
                Label("Skills", systemImage: "lightbulb")
            }
            .tag(ScarfGoCoordinator.Tab.skills)
            .accessibilityLabel("Skills tab")

            // 5 — System: server identity, Memory, Cron, Settings, plus
            // the destructive disconnect / forget actions. Renamed from
            // "More" to match the user-facing v2.5 vocabulary; the
            // .sidebarAdaptable system fallback label happens not to
            // matter here because we never overflow.
            NavigationStack {
                SystemTab(
                    config: config,
                    onSoftDisconnect: onSoftDisconnect,
                    onForget: onForget
                )
            }
            .tabItem {
                Label("System", systemImage: "gearshape.fill")
            }
            .tag(ScarfGoCoordinator.Tab.system)
            .accessibilityLabel("System tab")
        }
        // Pulls the sidebar-on-iPad affordance into the same code path
        // as the bottom-bar-on-iPhone one. No-op on iPhone today.
        .tabViewStyle(.sidebarAdaptable)
        .onAppear {
            synchronizeConversationPresentation(for: coordinator.selectedTab)
        }
        .onChange(of: coordinator.selectedTab) { _, selectedTab in
            synchronizeConversationPresentation(for: selectedTab)
        }
    }

    private func synchronizeConversationPresentation(for tab: ScarfGoCoordinator.Tab) {
        switch tab {
        case .text:
            voiceController.selectMode(.text)
        case .voice:
            voiceController.selectMode(.voice)
        case .dashboard, .skills, .system:
            break
        }
    }
}

/// Server identity + Memory + Cron + Settings + destructive actions.
/// "System" reads as configuration / server-meta; the reorganization
/// in v2.5 promotes Skills out of here into its own primary tab and
/// pulls Memory in from a primary tab into a NavigationLink row.
///
/// Kept private to this file because we don't expect it to be reused
/// elsewhere — if a feature graduates to a primary tab, that's a
/// deliberate design decision.
private struct SystemTab: View {
    let config: IOSServerConfig
    let onSoftDisconnect: @MainActor @Sendable () async -> Void
    let onForget: @MainActor @Sendable () async -> Void

    @Environment(\.hermesCapabilities) private var capabilitiesStore

    @State private var showForgetConfirmation = false
    @State private var isForgetting = false
    @State private var isDisconnecting = false
    /// Mirror of `SSHKeyICloudPreference.isEnabled` — drives the iCloud
    /// Keychain sync toggle (issue #52). Initial value is read on view
    /// init so the toggle reflects today's preference before the user
    /// taps anything; flipping triggers `migrateAllItems(toICloudSync:)`.
    @State private var iCloudSyncEnabled: Bool = SSHKeyICloudPreference.isEnabled
    @State private var iCloudMigrationInFlight = false
    @State private var iCloudMigrationError: String?

    // Explicit init so the closure params keep their `@Sendable` annotation —
    // the synthesized memberwise init dropped it, forcing a non-Sendable→
    // Sendable conversion at the call site (Swift-6 data-race warning).
    init(
        config: IOSServerConfig,
        onSoftDisconnect: @escaping @MainActor @Sendable () async -> Void,
        onForget: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.config = config
        self.onSoftDisconnect = onSoftDisconnect
        self.onForget = onForget
    }

    var body: some View {
        List {
            Section("Server") {
                LabeledContent("Host", value: config.host)
                    .listRowBackground(ScarfColor.backgroundSecondary)
                if let user = config.user {
                    LabeledContent("User", value: user)
                        .listRowBackground(ScarfColor.backgroundSecondary)
                }
                if let port = config.port {
                    LabeledContent("Port", value: String(port))
                        .listRowBackground(ScarfColor.backgroundSecondary)
                }
            }

            Section("Features") {
                NavigationLink {
                    ProjectsListView(config: config)
                } label: {
                    Label("Projects", systemImage: "square.grid.2x2")
                }
                .scarfGoCompactListRow()
                .listRowBackground(ScarfColor.backgroundSecondary)
                NavigationLink {
                    MemoryListView(config: config)
                } label: {
                    Label("Memory", systemImage: "brain.head.profile")
                }
                .scarfGoCompactListRow()
                .listRowBackground(ScarfColor.backgroundSecondary)
                if capabilitiesStore?.capabilities.hasCurator ?? false {
                    NavigationLink {
                        // `config` here is the profile-scoped effectiveConfig, so
                        // Curator's profile scoping rides on `paths` (remoteHome) —
                        // NOT on this fixed context id, which only keys the shared
                        // connection/home cache. Keep it that way: never branch
                        // Curator behavior on the context id (#120).
                        CuratorView(context: config.toServerContext(id: ScarfGoTabRoot.systemTabContextID))
                    } label: {
                        Label("Curator", systemImage: "sparkles")
                    }
                    .scarfGoCompactListRow()
                    .listRowBackground(ScarfColor.backgroundSecondary)
                }
                NavigationLink {
                    CronListView(config: config)
                } label: {
                    Label("Cron jobs", systemImage: "clock.arrow.circlepath")
                }
                .scarfGoCompactListRow()
                .listRowBackground(ScarfColor.backgroundSecondary)
                NavigationLink {
                    SettingsView(config: config)
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .scarfGoCompactListRow()
                .listRowBackground(ScarfColor.backgroundSecondary)
            }

            // v2.6: read-only mobile views over CLI-driven Hermes
            // surfaces. Mac owns the create/edit paths; phones get a
            // monitoring window into what the remote agent is honoring.
            // None of these are capability-gated — the underlying
            // `hermes plugins/profile/webhook list` verbs exist on
            // both v0.11 and v0.12, so the read views work on either.
            Section("Inspect") {
                NavigationLink {
                    WebhooksView(config: config)
                } label: {
                    Label("Webhooks", systemImage: "arrow.up.right.square")
                }
                .scarfGoCompactListRow()
                .listRowBackground(ScarfColor.backgroundSecondary)
                NavigationLink {
                    PluginsView(config: config)
                } label: {
                    Label("Plugins", systemImage: "app.badge.checkmark")
                }
                .scarfGoCompactListRow()
                .listRowBackground(ScarfColor.backgroundSecondary)
                NavigationLink {
                    ProfilesView(config: config)
                } label: {
                    Label("Profiles", systemImage: "person.2.crop.square.stack")
                }
                .scarfGoCompactListRow()
                .listRowBackground(ScarfColor.backgroundSecondary)
            }

            Section {
                Toggle(isOn: $iCloudSyncEnabled) {
                    HStack(spacing: 10) {
                        Image(systemName: "key.icloud.fill")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync SSH key with iCloud Keychain")
                            Text(iCloudSyncEnabled
                                 ? "Synced — your other Apple devices with iCloud Keychain will see this key."
                                 : "This device only — generate a separate key on each device.")
                                .font(.caption)
                                .foregroundStyle(ScarfColor.foregroundMuted)
                        }
                    }
                }
                .tint(ScarfColor.accent)
                .disabled(iCloudMigrationInFlight)
                .onChange(of: iCloudSyncEnabled) { _, newValue in
                    Task {
                        iCloudMigrationInFlight = true
                        iCloudMigrationError = nil
                        defer { iCloudMigrationInFlight = false }
                        do {
                            try await KeychainSSHKeyStore().migrateAllItems(toICloudSync: newValue)
                        } catch {
                            // Revert the toggle on failure so the UI
                            // reflects what's actually in the Keychain;
                            // surface the error inline so the user can
                            // retry / report. Keychain failures here are
                            // rare (typically `errSecDuplicateItem` if a
                            // prior migration was interrupted — the
                            // delete-with-Any in writeBundle prevents
                            // that, but we still belt-and-brace).
                            iCloudMigrationError = error.localizedDescription
                            iCloudSyncEnabled = !newValue
                            SSHKeyICloudPreference.isEnabled = !newValue
                        }
                    }
                }
                if iCloudMigrationInFlight {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Updating Keychain…")
                            .font(.caption)
                            .foregroundStyle(ScarfColor.foregroundMuted)
                    }
                }
                if let err = iCloudMigrationError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(ScarfColor.warning)
                }
            } header: {
                Text("Security")
            } footer: {
                Text("End-to-end encrypted via iCloud Keychain. With Advanced Data Protection on, the encryption keys never leave your devices. Toggle off to keep the key device-only — each new device must onboard separately.")
                    .font(.caption)
            }
            .listRowBackground(ScarfColor.backgroundSecondary)

            Section {
                Button {
                    Task {
                        isDisconnecting = true
                        await onSoftDisconnect()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isDisconnecting {
                            ProgressView()
                        } else {
                            Text("Disconnect")
                        }
                        Spacer()
                    }
                }
                .disabled(isDisconnecting || isForgetting)
                .listRowBackground(ScarfColor.backgroundSecondary)
            } footer: {
                Text("Closes the live connection. Your key and host details stay on this device; tapping the server from the list reconnects with no re-onboarding.")
                    .font(.caption)
            }

            Section {
                Button(role: .destructive) {
                    showForgetConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if isForgetting {
                            ProgressView()
                        } else {
                            Text("Forget this server")
                        }
                        Spacer()
                    }
                }
                .disabled(isForgetting || isDisconnecting)
                .listRowBackground(ScarfColor.backgroundSecondary)
            } footer: {
                Text("Removes this server's SSH key and host info from the device. You'll need to add the public key back to `~/.ssh/authorized_keys` to reconnect.")
                    .font(.caption)
            }
        }
        .scarfGoListDensity()
        .scrollContentBackground(.hidden)
        .background(ScarfColor.backgroundPrimary)
        .navigationTitle("System")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Forget this server?",
            isPresented: $showForgetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forget \(config.displayName)", role: .destructive) {
                Task {
                    isForgetting = true
                    await onForget()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your SSH key and host settings for \(config.displayName) will be removed. Other servers stay configured. This cannot be undone.")
        }
    }
}
