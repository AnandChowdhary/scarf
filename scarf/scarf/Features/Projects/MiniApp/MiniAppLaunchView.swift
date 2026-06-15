import SwiftUI
import ScarfCore
import ScarfDesign

/// Cockpit "Mini-apps" panel — lists the project's mini-apps and launches
/// one through the permission gate into the sandboxed host.
struct CockpitMiniAppsPanel: View {
    let project: ScarfProject?
    let manifests: [MiniAppManifest]
    let serverContext: ServerContext

    @State private var launching: MiniAppManifest?

    var body: some View {
        Group {
            if let project, !manifests.isEmpty {
                List(manifests) { manifest in
                    row(manifest, project: project)
                }
                .listStyle(.plain)
            } else if project == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CockpitEmptyState(
                    icon: "square.grid.2x2",
                    text: "No mini-apps in this project yet. Drop one in `.scarf/miniapps/<id>/` or have the agent build one."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $launching) { manifest in
            if let project {
                MiniAppLaunchSheet(project: project, manifest: manifest, serverContext: serverContext)
            }
        }
    }

    private func row(_ manifest: MiniAppManifest, project: ScarfProject) -> some View {
        HStack(spacing: 10) {
            Image(systemName: manifest.generated ? "wand.and.stars" : "square.grid.2x2")
                .foregroundStyle(manifest.generated ? ScarfColor.warning : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(manifest.name).font(.callout)
                    if manifest.generated {
                        Text("agent-generated").font(.caption2)
                            .foregroundStyle(ScarfColor.warning)
                    }
                }
                Text(permissionSummary(manifest))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") { launching = manifest }
                .buttonStyle(ScarfSecondaryButton())
        }
        .padding(.vertical, 2)
    }

    private func permissionSummary(_ manifest: MiniAppManifest) -> String {
        manifest.permissions.isEmpty
            ? "v\(manifest.version) · no permissions requested"
            : "v\(manifest.version) · \(manifest.permissions.count) permission\(manifest.permissions.count == 1 ? "" : "s") requested"
    }
}

// MARK: - Launch flow (permission gate → runner)

/// Drives one mini-app launch: shows the permission preview when there's no
/// prior decision, then hosts the sandboxed mini-app with the granted set.
struct MiniAppLaunchSheet: View {
    let project: ScarfProject
    let manifest: MiniAppManifest
    let serverContext: ServerContext

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var granted: Set<MiniAppPermission> = []

    private enum Phase { case loading, incompatible, review, run }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .incompatible:
                CockpitEmptyState(
                    icon: "exclamationmark.triangle",
                    text: "“\(manifest.name)” needs a newer mini-app bridge (requires \(manifest.minBridgeVersion); this Scarf provides \(miniAppBridgeVersion)). Update Scarf to run it."
                )
            case .review:
                MiniAppPermissionPreview(
                    manifest: manifest,
                    onApprove: { approved in
                        save(approved)
                        granted = approved
                        phase = .run
                    },
                    onCancel: { dismiss() }
                )
            case .run:
                MiniAppRunner(
                    project: project,
                    manifest: manifest,
                    serverContext: serverContext,
                    granted: granted,
                    onReviewPermissions: { phase = .review },
                    onClose: { dismiss() }
                )
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .task(id: manifest.id) {
            // Version gate first: refuse a mini-app built against a newer
            // bridge contract rather than silently half-running it.
            guard MiniAppBridge.satisfiesMinBridgeVersion(manifest.minBridgeVersion) else {
                phase = .incompatible
                return
            }
            let store = MiniAppGrantStore(context: serverContext)
            let pid = project.id.uuidString
            if store.hasDecision(projectId: pid, miniAppId: manifest.id) {
                granted = store.grantedPermissions(projectId: pid, miniAppId: manifest.id)
                phase = .run
            } else {
                phase = .review
            }
        }
    }

    private func save(_ permissions: Set<MiniAppPermission>) {
        try? MiniAppGrantStore(context: serverContext).setGrant(
            projectId: project.id.uuidString,
            miniAppId: manifest.id,
            permissions: permissions
        )
    }
}

/// The trust-boundary sheet: every declared surface, sensitive ones
/// highlighted, default-off for agent-generated apps. Approve grants
/// exactly the checked set; unknown permissions can never be granted.
struct MiniAppPermissionPreview: View {
    let manifest: MiniAppManifest
    let onApprove: (Set<MiniAppPermission>) -> Void
    let onCancel: () -> Void

    @State private var checked: Set<MiniAppPermission> = []

    /// Permissions that can actually be toggled (unknowns are shown but
    /// never grantable).
    private var grantable: [MiniAppPermission] {
        manifest.permissions.filter { if case .unknown = $0 { return false }; return true }
    }
    private var unknowns: [MiniAppPermission] {
        manifest.permissions.filter { if case .unknown = $0 { return true }; return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(manifest.name) wants permission")
                    .font(.headline)
                Text(manifest.generated
                     ? "This mini-app was generated by the agent. Sensitive permissions are off by default — turn on only what you trust."
                     : "Review what this mini-app can access before running it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            Divider()

            if manifest.permissions.isEmpty {
                CockpitEmptyState(icon: "checkmark.shield", text: "This mini-app requests no permissions.")
            } else {
                List {
                    ForEach(grantable, id: \.self) { perm in
                        Toggle(isOn: Binding(
                            get: { checked.contains(perm) },
                            set: { if $0 { checked.insert(perm) } else { checked.remove(perm) } }
                        )) {
                            permissionRow(perm)
                        }
                    }
                    ForEach(unknowns, id: \.self) { perm in
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle").foregroundStyle(ScarfColor.warning)
                            Text(perm.summary).font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Text("denied").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Approve & Run") { onApprove(checked) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .task { checked = defaultChecked() }
    }

    private func permissionRow(_ perm: MiniAppPermission) -> some View {
        HStack(spacing: 8) {
            Image(systemName: perm.isSensitive ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .foregroundStyle(perm.isSensitive ? ScarfColor.warning : .secondary)
            Text(perm.summary).font(.callout)
            if perm.isSensitive {
                Text("sensitive").font(.caption2).foregroundStyle(ScarfColor.warning)
            }
        }
    }

    /// Default selection: non-sensitive on; sensitive off for
    /// agent-generated apps, on for hand-authored/template ones (still
    /// user-overridable).
    private func defaultChecked() -> Set<MiniAppPermission> {
        Set(grantable.filter { !$0.isSensitive || !manifest.generated })
    }
}

/// Hosts the running mini-app with a slim chrome (close + re-review perms).
private struct MiniAppRunner: View {
    let project: ScarfProject
    let manifest: MiniAppManifest
    let serverContext: ServerContext
    let granted: Set<MiniAppPermission>
    let onReviewPermissions: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(manifest.name).font(.headline)
                Spacer()
                Button {
                    onReviewPermissions()
                } label: {
                    Label("Permissions", systemImage: "lock.shield")
                }
                .buttonStyle(.borderless)
                .help("Review or change what this mini-app can access")
                Button("Close") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(8)
            Divider()
            MiniAppHostView(
                project: project,
                manifest: manifest,
                serverContext: serverContext,
                grantedPermissions: granted
            )
            // Recreate the web host (fresh dispatcher) whenever the granted
            // set changes — so re-reviewing to a NARROWER set actually
            // revokes access on the live instance, not just on next launch.
            .id(manifest.id + "|" + granted.map(\.rawValue).sorted().joined(separator: ","))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
