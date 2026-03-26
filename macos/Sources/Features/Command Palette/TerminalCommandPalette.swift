import SwiftUI
import GhosttyKit

struct TerminalCommandPaletteView: View {
    /// The surface that this command palette represents.
    let surfaceView: Ghostty.SurfaceView

    /// Set this to true to show the view, this will be set to false if any actions
    /// result in the view disappearing.
    @Binding var isPresented: Bool

    /// The configuration so we can lookup keyboard shortcuts.
    @ObservedObject var ghosttyConfig: Ghostty.Config

    /// The update view model for showing update commands.
    var updateViewModel: UpdateViewModel?

    /// The callback when an action is submitted.
    var onAction: ((String) -> Void)

    var body: some View {
        ZStack {
            if isPresented {
                GeometryReader { geometry in
                    VStack {
                        Spacer().frame(height: geometry.size.height * 0.05)

                        ResponderChainInjector(responder: surfaceView)
                            .frame(width: 0, height: 0)

                        CommandPaletteView(
                            isPresented: $isPresented,
                            backgroundColor: ghosttyConfig.backgroundColor,
                            placeholder: palettePlaceholder,
                            preselectIndex: palettePreselectIndex,
                            options: commandOptions
                        )
                        .zIndex(1) // Ensure it's on top

                        Spacer()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                }
            }
        }
        .onChange(of: isPresented) { newValue in
            // When the command palette disappears we need to send focus back to the
            // surface view we were overlaid on top of. There's probably a better way
            // to handle the first responder state here but I don't know it.
            if !newValue {
                #if GHOSTTY_IDE
                IDEPaletteState.mode = .commands
                #endif
                // Has to be on queue because onChange happens on a user-interactive
                // thread and Xcode is mad about this call on that.
                DispatchQueue.main.async {
                    surfaceView.window?.makeFirstResponder(surfaceView)
                }
            }
        }
    }

    private var palettePlaceholder: String {
        #if GHOSTTY_IDE
        if IDEPaletteState.mode == .projects {
            let active = WorkspaceController.shared.activeProject
            if !active.isEmpty {
                return "Current: \(active) — switch to…"
            }
            return "Switch to a project…"
        }
        #endif
        return "Execute a command…"
    }

    private var palettePreselectIndex: UInt? {
        #if GHOSTTY_IDE
        if IDEPaletteState.mode == .projects {
            let active = WorkspaceController.shared.activeProject
            if let idx = WorkspaceController.shared.projects.firstIndex(of: active) {
                return UInt(idx)
            }
        }
        #endif
        return nil
    }

    /// All commands available in the command palette, combining update and terminal options.
    /// In project picker mode (Cmd+P), shows only project options.
    private var commandOptions: [CommandOption] {
        #if GHOSTTY_IDE
        if IDEPaletteState.mode == .projects {
            return IDEProjectPickerOptions.options(onNewProject: { self.handleProjectNew() })
        }
        #endif

        var options: [CommandOption] = []
        // Updates always appear first
        options.append(contentsOf: updateOptions)

        // Sort the rest. We replace ":" with a character that sorts before space
        // so that "Foo:" sorts before "Foo Bar:". Use sortKey as a tie-breaker
        // for stable ordering when titles are equal.
        #if GHOSTTY_IDE
        let ideOpts = IDECommandPaletteOptions.options(
            onSaveProject: { self.handleProjectSave() },
            onRestoreProject: { name in let _ = try? WorkspaceManager.shared.restore(name: name) },
            onDeleteProject: { name in let _ = try? WorkspaceStore.shared.delete(name: name) },
            onNewWorkspace: { self.handleWorkspaceNew() },
            onRenameWorkspace: { self.handleWorkspaceRename() },
            onRenameProject: { self.handleProjectRename() },
            onNewProject: { self.handleProjectNew() }
        )
        #else
        let ideOpts: [CommandOption] = []
        #endif

        options.append(contentsOf: (jumpOptions + terminalOptions + ideOpts).sorted { a, b in
            let aNormalized = a.title.replacingOccurrences(of: ":", with: "\t")
            let bNormalized = b.title.replacingOccurrences(of: ":", with: "\t")
            let comparison = aNormalized.localizedCaseInsensitiveCompare(bNormalized)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            // Tie-breaker: use sortKey if both have one
            if let aSortKey = a.sortKey, let bSortKey = b.sortKey {
                return aSortKey < bSortKey
            }
            return false
        })
        return options
    }

    /// Commands for installing or canceling available updates.
    private var updateOptions: [CommandOption] {
        var options: [CommandOption] = []

        guard let updateViewModel, updateViewModel.state.isInstallable else {
            return options
        }

        // We override the update available one only because we want to properly
        // convey it'll go all the way through.
        let title: String
        if case .updateAvailable = updateViewModel.state {
            #if GHOSTTY_IDE
            title = "Update \(AppBrand.name) and Restart"
            #else
            title = "Update Ghostty and Restart"
            #endif
        } else {
            title = updateViewModel.text
        }

        options.append(CommandOption(
            title: title,
            description: updateViewModel.description,
            leadingIcon: updateViewModel.iconName ?? "shippingbox.fill",
            badge: updateViewModel.badge,
            emphasis: true
        ) {
            (NSApp.delegate as? AppDelegate)?.updateController.installUpdate()
        })

        options.append(CommandOption(
            title: "Cancel or Skip Update",
            description: "Dismiss the current update process"
        ) {
            updateViewModel.state.cancel()
        })

        return options
    }

    /// Custom commands from the command-palette-entry configuration.
    private var terminalOptions: [CommandOption] {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return [] }
        return appDelegate.ghostty.config.commandPaletteEntries
            .filter(\.isSupported)
            .map { c in
                let symbols = appDelegate.ghostty.config.keyboardShortcut(for: c.action)?.keyList
                return CommandOption(
                    title: c.title,
                    description: c.description,
                    symbols: symbols
                ) {
                    onAction(c.action)
                }
            }
    }

    #if GHOSTTY_IDE
    private func handleProjectSave() {
        let alert = NSAlert()
        alert.messageText = "Save Project"
        alert.informativeText = "Enter a name for this project:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "my-project"
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                let _ = try? WorkspaceManager.shared.save(name: name)
            }
        }
    }

    private func handleWorkspaceNew() {
        let controller = WorkspaceController.shared
        let alert = NSAlert()
        alert.messageText = "New Workspace"
        alert.informativeText = "Enter a name for the new workspace:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "workspace-name"
        alert.accessoryView = input
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                let project = controller.activeProject.isEmpty ? "default" : controller.activeProject
                let ws = controller.addWorkspace(name: name, project: project)
                controller.switchTo(workspace: ws)
            }
        }
    }

    private func handleWorkspaceRename() {
        let controller = WorkspaceController.shared
        guard let active = controller.activeWorkspace else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Workspace"
        alert.informativeText = "Enter a new name:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = active.name
        alert.accessoryView = input
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                controller.renameWorkspace(id: active.id, name: name)
            }
        }
    }

    private func handleProjectRename() {
        let controller = WorkspaceController.shared
        let current = controller.activeProject
        guard !current.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Project"
        alert.informativeText = "Rename '\(current)' to:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = current
        alert.accessoryView = input
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                let _ = controller.renameProject(from: current, to: name)
            }
        }
    }

    private func handleProjectNew() {
        let controller = WorkspaceController.shared
        let alert = NSAlert()
        alert.messageText = "New Project"
        alert.informativeText = "Enter a name for the project:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "PROJECT-NAME"
        alert.accessoryView = input
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                let ws = controller.addWorkspace(name: "main", project: name)
                controller.switchProject(name: name)
                controller.switchTo(workspace: ws)
            }
        }
    }
    #endif

    /// Commands for jumping to other terminal surfaces.
    private var jumpOptions: [CommandOption] {
        TerminalController.all.flatMap { controller -> [CommandOption] in
            guard let window = controller.window else { return [] }

            let color = (window as? TerminalWindow)?.tabColor
            let displayColor = color != TerminalTabColor.none ? color : nil

            return controller.surfaceTree.map { surface in
                let terminalTitle = surface.title.isEmpty ? window.title : surface.title
                let displayTitle: String
                if let override = controller.titleOverride, !override.isEmpty {
                    displayTitle = override
                } else if !terminalTitle.isEmpty {
                    displayTitle = terminalTitle
                } else {
                    displayTitle = "Untitled"
                }
                let pwd = surface.pwd?.abbreviatedPath
                let subtitle: String? = if let pwd, !displayTitle.contains(pwd) {
                    pwd
                } else {
                    nil
                }

                return CommandOption(
                    title: "Focus: \(displayTitle)",
                    subtitle: subtitle,
                    leadingIcon: "rectangle.on.rectangle",
                    leadingColor: displayColor?.displayColor.map { Color($0) },
                    sortKey: AnySortKey(ObjectIdentifier(surface))
                ) {
                    NotificationCenter.default.post(
                        name: Ghostty.Notification.ghosttyPresentTerminal,
                        object: surface
                    )
                }
            }
        }
    }

}

/// This is done to ensure that the given view is in the responder chain.
private struct ResponderChainInjector: NSViewRepresentable {
    let responder: NSResponder

    func makeNSView(context: Context) -> NSView {
        let dummy = NSView()
        DispatchQueue.main.async {
            dummy.nextResponder = responder
        }
        return dummy
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
