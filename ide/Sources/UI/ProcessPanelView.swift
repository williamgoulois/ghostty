import SwiftUI

/// Process monitor panel shown as a popover from the top bar.
/// Lists AI agents and long-running processes with kill controls.
struct ProcessPanelView: View {
    @Binding var isPresented: Bool
    let snapshots: [UUID: WorkspaceProcessSnapshot]
    let onJumpToPane: (String) -> Void
    let onKillProcess: (pid_t, Int32) -> Void
    @State private var showKillAllConfirm = false

    private var allProcesses: [DetectedProcess] {
        snapshots.values.flatMap(\.processes)
    }

    private var hasContent: Bool {
        allProcesses.contains { $0.category == .agent || $0.category == .longRunning }
    }

    private var agents: [DetectedProcess] {
        allProcesses.filter { $0.category == .agent }
    }

    private var longRunning: [DetectedProcess] {
        allProcesses.filter { $0.category == .longRunning }
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

            if hasContent {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // AI Agents section
                        if !agents.isEmpty {
                            PanelSectionHeader(title: "AI Agents", icon: "bolt.fill")
                            ForEach(agents) { proc in
                                ProcessRow(
                                    process: proc,
                                    onJump: onJumpToPane,
                                    onKill: { onKillProcess(proc.pid, SIGINT) }
                                )
                                Divider().padding(.leading, 12)
                            }
                        }

                        // Long-running processes section
                        if !longRunning.isEmpty {
                            PanelSectionHeader(title: "Running", icon: "hourglass")
                            ForEach(longRunning) { proc in
                                ProcessRow(
                                    process: proc,
                                    onJump: onJumpToPane,
                                    onKill: { onKillProcess(proc.pid, SIGINT) }
                                )
                                Divider().padding(.leading, 12)
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
        .frame(width: 320, height: 360)
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

/// Port monitor panel shown as a popover from the top bar.
/// Lists listening TCP ports across all workspaces.
struct PortPanelView: View {
    @Binding var isPresented: Bool
    let snapshots: [UUID: WorkspaceProcessSnapshot]
    let onJumpToPane: (String) -> Void

    private var allPorts: [DetectedPort] {
        snapshots.values.flatMap(\.ports).sorted { $0.port < $1.port }
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
                        ForEach(allPorts) { port in
                            PortRow(port: port, onJumpToPane: onJumpToPane)
                            Divider().padding(.leading, 12)
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
        .frame(width: 300, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Shared Subviews

struct PanelSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
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
        .padding(.horizontal, 12)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            onJump(process.paneId.uuidString)
        }
    }
}
