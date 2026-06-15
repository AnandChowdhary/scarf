import SwiftUI
import ScarfCore
import ScarfDesign

/// Per-project "mission control" — the aggregate destination the
/// Phase-1 design calls for. One place that owns a project across every
/// facet, rendered from its first-class `ScarfProject` record.
///
/// **Header**: name · root path · bound model · host badges.
/// **Panels** (reuse where one already exists): Sessions
/// (`ProjectSessionsView`), Board (`ProjectKanbanTab`, gated on
/// `hasKanban`), and new lightweight read-only panels — Context
/// (AGENTS.md block), Cron (`[proj:]`/`[tmpl:]` jobs), Memory (MEMORY.md
/// block), Secrets (ref NAMES only — SECRET-SAFE), Templates.
///
/// Mini-apps are Milestone 2. Tool/skill scoping is deferred (upstream
/// hermes-agent#45958), so there is deliberately no Scope panel yet.
struct ProjectCockpitView: View {
    let project: ProjectEntry

    @Environment(\.serverContext) private var serverContext
    @Environment(\.hermesCapabilities) private var capabilitiesStore
    @Environment(HermesFileWatcher.self) private var fileWatcher

    @State private var viewModel: ProjectCockpitViewModel?
    @State private var selectedPanel: CockpitPanel = .sessions

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 10)
            Divider()
            panelBar
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            panelContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: project.id) {
            // Rebuild the VM when the selected project changes so stale
            // facet data doesn't bleed across projects.
            let vm = ProjectCockpitViewModel(context: serverContext, project: project)
            viewModel = vm
            await vm.load()
        }
        .onChange(of: fileWatcher.lastChangeDate) {
            Task { await viewModel?.load(force: true) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.title2.bold())
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    modelBadge
                    hostBadges
                }
                .padding(.top, 2)
            }
            Spacer()
        }
    }

    private var modelBadge: some View {
        let name = viewModel?.modelPresetName
        return Label(name.map { "Model: \($0)" } ?? "Model: default", systemImage: "cpu")
            .font(.caption)
            .foregroundStyle(name == nil ? ScarfColor.foregroundMuted : ScarfColor.accentActive)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(name == nil ? Color.clear : ScarfColor.accentTint)
            .clipShape(Capsule())
            .help(name == nil
                ? "No model preset bound — inherits the global default."
                : "Applied at session boot via session/set_model.")
    }

    @ViewBuilder
    private var hostBadges: some View {
        let bindings = viewModel?.scarfProject?.hostBindings ?? []
        ForEach(bindings, id: \.serverId) { binding in
            Label(hostLabel(for: binding.serverId), systemImage: "server.rack")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ScarfColor.backgroundTertiary)
                .clipShape(Capsule())
                .help("This project is materialized on this host.")
        }
    }

    /// "Local" for the well-known local server id; a short id prefix
    /// otherwise. (Full fleet/portfolio naming arrives with multi-host
    /// materialization in a later phase.)
    private func hostLabel(for serverId: String) -> String {
        if serverId == ServerContext.local.id.uuidString { return "Local" }
        if serverId == serverContext.id.uuidString { return serverContext.displayName }
        return String(serverId.prefix(8))
    }

    // MARK: - Panel bar

    private var visiblePanels: [CockpitPanel] {
        let hasKanban = capabilitiesStore?.capabilities.hasKanban ?? false
        return CockpitPanel.allCases.filter { panel in
            switch panel {
            case .board: return hasKanban
            default:     return true
            }
        }
    }

    private var panelBar: some View {
        HStack(spacing: 0) {
            ForEach(visiblePanels, id: \.self) { panel in
                Button {
                    selectedPanel = panel
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: panel.systemImage)
                            .font(.caption)
                        Text(panel.title)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedPanel == panel ? ScarfColor.accentTint : Color.clear)
                    .foregroundStyle(selectedPanel == panel ? ScarfColor.accentActive : ScarfColor.foregroundMuted)
                    .clipShape(RoundedRectangle(cornerRadius: ScarfRadius.md))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Panel content

    @ViewBuilder
    private var panelContent: some View {
        switch selectedPanel {
        case .sessions:
            // Reuse the existing per-project Sessions view verbatim.
            ProjectSessionsView(project: project)
        case .board:
            // Reuse the existing per-project Kanban tab (gated above).
            ProjectKanbanTab(project: project)
        case .context:
            CockpitContextPanel(block: viewModel?.contextBlock, isLoading: viewModel?.isLoading ?? true)
        case .cron:
            CockpitCronPanel(jobs: viewModel?.cronJobs ?? [], isLoading: viewModel?.isLoading ?? true)
        case .memory:
            CockpitMemoryPanel(
                namespace: viewModel?.scarfProject?.memoryNamespace,
                block: viewModel?.memoryBlock
            )
        case .secrets:
            CockpitSecretsPanel(names: viewModel?.scarfProject?.secretsScope ?? [])
        case .templates:
            CockpitTemplatesPanel(
                templateID: viewModel?.templateID,
                templateVersion: viewModel?.templateVersion,
                lockRef: viewModel?.scarfProject?.templateLockRef
            )
        case .miniapps:
            CockpitMiniAppsPanel(
                project: viewModel?.scarfProject,
                manifests: viewModel?.miniApps ?? [],
                serverContext: serverContext
            )
        }
    }
}

// MARK: - Panel identity

private enum CockpitPanel: String, CaseIterable {
    case sessions, board, context, cron, memory, secrets, templates, miniapps

    var title: String {
        switch self {
        case .sessions:  return "Sessions"
        case .board:     return "Board"
        case .context:   return "Context"
        case .cron:      return "Cron"
        case .memory:    return "Memory"
        case .secrets:   return "Secrets"
        case .templates: return "Templates"
        case .miniapps:  return "Mini-apps"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions:  return "bubble.left.and.bubble.right"
        case .board:     return "rectangle.split.3x1"
        case .context:   return "doc.text"
        case .cron:      return "clock"
        case .memory:    return "brain"
        case .secrets:   return "key"
        case .templates: return "shippingbox"
        case .miniapps:  return "square.grid.2x2"
        }
    }
}

// MARK: - Lightweight panels

/// Read-only preview of the Scarf-managed AGENTS.md block — the
/// projection of the `ScarfProject` the agent actually sees.
private struct CockpitContextPanel: View {
    let block: String?
    let isLoading: Bool

    var body: some View {
        Group {
            if let block, !block.isEmpty {
                ScrollView {
                    Text(block)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CockpitEmptyState(
                    icon: "doc.text",
                    text: "No Scarf-managed AGENTS.md block yet. It's written on the next project-scoped chat."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Cron jobs attributed to this project (`[proj:<id>]` / `[tmpl:<id>]`).
private struct CockpitCronPanel: View {
    let jobs: [HermesCronJob]
    let isLoading: Bool

    var body: some View {
        Group {
            if !jobs.isEmpty {
                List(jobs) { job in
                    HStack(spacing: 10) {
                        Image(systemName: job.enabled ? "clock.fill" : "pause.circle")
                            .foregroundStyle(job.enabled ? ScarfColor.success : ScarfColor.foregroundMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.name).font(.callout).lineLimit(1)
                            Text(scheduleText(job))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(job.enabled ? "enabled" : "paused")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CockpitEmptyState(
                    icon: "clock",
                    text: "No cron jobs attributed to this project."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scheduleText(_ job: HermesCronJob) -> String {
        job.schedule.display ?? job.schedule.expression ?? job.schedule.kind
    }
}

/// The project's MEMORY.md block, when it owns one.
private struct CockpitMemoryPanel: View {
    let namespace: String?
    let block: String?

    var body: some View {
        Group {
            if let block, !block.isEmpty {
                ScrollView {
                    Text(block)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else if let namespace {
                CockpitEmptyState(
                    icon: "brain",
                    text: "Memory namespace `\(namespace)` is bound, but no matching block was found in MEMORY.md."
                )
            } else {
                CockpitEmptyState(
                    icon: "brain",
                    text: "This project has no memory block."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Secret field NAMES only — values stay in the Keychain (SECRET-SAFE).
private struct CockpitSecretsPanel: View {
    let names: [String]

    var body: some View {
        Group {
            if !names.isEmpty {
                List(names, id: \.self) { name in
                    HStack(spacing: 10) {
                        Image(systemName: "key.fill").foregroundStyle(ScarfColor.warning)
                        Text(name).font(.callout.monospaced())
                        Spacer()
                        Text("Keychain — name only")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            } else {
                CockpitEmptyState(
                    icon: "key",
                    text: "This project declares no secret configuration fields."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Installed-template id/version + the uninstall lock reference.
private struct CockpitTemplatesPanel: View {
    let templateID: String?
    let templateVersion: String?
    let lockRef: String?

    var body: some View {
        Group {
            if let templateID {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Template") {
                        Text("\(templateID)\(templateVersion.map { " v\($0)" } ?? "")")
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    if let lockRef {
                        LabeledContent("Uninstall manifest") {
                            Text(lockRef)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                CockpitEmptyState(
                    icon: "shippingbox",
                    text: "This project wasn't installed from a template."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shared empty-state for the lightweight panels.
struct CockpitEmptyState: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
