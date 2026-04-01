import SwiftUI

// MARK: - Grouping Helper

/// A project → workspace → items grouping for panel display.
private struct PanelGroup<Item> {
    let project: String
    let workspace: String
    let workspaceId: UUID
    let items: [Item]
}

/// Group items by project then workspace using WorkspaceController lookup.
private func groupByProjectWorkspace<Item>(
    _ items: [Item],
    workspaceId: (Item) -> UUID,
    workspaceName: (Item) -> String
) -> [(project: String, workspaces: [(name: String, id: UUID, items: [Item])])] {
    // Look up project for each workspace ID
    let wsLookup = Dictionary(
        uniqueKeysWithValues: WorkspaceController.shared.workspaces.map { ($0.id, $0.project) }
    )

    // Group by project, then by workspace
    var byProject: [String: [UUID: (name: String, items: [Item])]] = [:]
    for item in items {
        let wsId = workspaceId(item)
        let project = wsLookup[wsId] ?? "Unknown"
        let wsName = workspaceName(item)
        byProject[project, default: [:]][wsId, default: (wsName, [])].items.append(item)
    }

    // Sort: projects alphabetically, workspaces alphabetically within each project
    return byProject
        .sorted { $0.key < $1.key }
        .map { project, workspaces in
            let sorted = workspaces
                .sorted { $0.value.name < $1.value.name }
                .map { (name: $0.value.name, id: $0.key, items: $0.value.items) }
            return (project: project, workspaces: sorted)
        }
}

// MARK: - Process Panel

/// Process monitor panel shown as a popover from the top bar.
/// Lists AI agents and long-running processes grouped by project/workspace.
struct ProcessPanelView: View {
    @Binding var isPresented: Bool
    let snapshots: [UUID: WorkspaceProcessSnapshot]
    let onJumpToPane: (String) -> Void
    let onKillProcess: (pid_t, Int32) -> Void
    @State private var showKillAllConfirm = false

    private var relevantProcesses: [DetectedProcess] {
        snapshots.values
            .flatMap(\.processes)
            .filter { $0.category == .agent || $0.category == .longRunning }
    }

    private var longRunning: [DetectedProcess] {
        relevantProcesses.filter { $0.category == .longRunning }
    }

    private var grouped: [(project: String, workspaces: [(name: String, id: UUID, items: [DetectedProcess])])] {
        groupByProjectWorkspace(
            relevantProcesses,
            workspaceId: \.workspaceId,
            workspaceName: \.workspaceName
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Processes")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !longRunning.isEmpty {
                    Button("Kill All") {
                        showKillAllConfirm = true
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if !relevantProcesses.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(grouped, id: \.project) { projectGroup in
                            PanelProjectHeader(name: projectGroup.project)
                            ForEach(projectGroup.workspaces, id: \.id) { wsGroup in
                                PanelWorkspaceHeader(name: wsGroup.name)
                                ForEach(wsGroup.items) { proc in
                                    ProcessRow(
                                        process: proc,
                                        onJump: onJumpToPane,
                                        onKill: { onKillProcess(proc.pid, SIGINT) }
                                    )
                                    Divider().padding(.leading, 24)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No active processes")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .frame(width: 340, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Kill All Processes", isPresented: $showKillAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Kill All", role: .destructive) {
                for proc in longRunning {
                    onKillProcess(proc.pid, SIGTERM)
                }
            }
        } message: {
            Text("Send SIGTERM to all running processes?")
        }
    }
}

// MARK: - Port Panel

/// Port monitor panel shown as a popover from the top bar.
/// Lists listening TCP ports grouped by project/workspace.
struct PortPanelView: View {
    @Binding var isPresented: Bool
    let snapshots: [UUID: WorkspaceProcessSnapshot]
    let onJumpToPane: (String) -> Void

    private var allPorts: [DetectedPort] {
        snapshots.values.flatMap(\.ports).sorted { $0.port < $1.port }
    }

    private var grouped: [(project: String, workspaces: [(name: String, id: UUID, items: [DetectedPort])])] {
        groupByProjectWorkspace(
            allPorts,
            workspaceId: \.workspaceId,
            workspaceName: \.workspaceName
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Listening Ports")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if !allPorts.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(grouped, id: \.project) { projectGroup in
                            PanelProjectHeader(name: projectGroup.project)
                            ForEach(projectGroup.workspaces, id: \.id) { wsGroup in
                                PanelWorkspaceHeader(name: wsGroup.name)
                                ForEach(wsGroup.items) { port in
                                    PortRow(port: port, onJumpToPane: onJumpToPane)
                                    Divider().padding(.leading, 24)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "network")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No listening ports")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .frame(width: 320, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Shared Subviews

struct PanelProjectHeader: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

struct PanelWorkspaceHeader: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 8))
            Text(name)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}

struct PortRow: View {
    let port: DetectedPort
    let onJumpToPane: (String) -> Void

    var body: some View {
        HStack {
            Image(systemName: "network")
                .font(.system(size: 10))
                .foregroundColor(.blue)
                .frame(width: 16)
            Text(verbatim: ":\(port.port)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            Text(port.processName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            if port.tls {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            onJumpToPane(port.paneId.uuidString)
        }
    }
}

struct ProcessRow: View {
    let process: DetectedProcess
    let onJump: (String) -> Void
    let onKill: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(process.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if let status = process.agentStatus {
                        Text("(\(status))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Text(verbatim: "PID \(process.pid)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onKill) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Kill process (SIGINT)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            onJump(process.paneId.uuidString)
        }
    }
}
