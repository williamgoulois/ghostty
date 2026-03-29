import Testing
@testable import GhosttyIDE

struct WorkspaceCommandTests {
    private let router = IDECommandRouter()

    // MARK: - project.save

    @Test func projectSaveMissingNameFails() {
        let response = router.dispatch(TestCommand.make("project.save"))
        #expect(!response.ok)
        #expect(response.error == "Missing project name")
    }

    @Test func projectSaveEmptyNameFails() {
        let response = router.dispatch(TestCommand.make("project.save", args: ["name": ""]))
        #expect(!response.ok)
        #expect(response.error == "Missing project name")
    }

    // MARK: - project.restore

    @Test func projectRestoreMissingNameFails() {
        let response = router.dispatch(TestCommand.make("project.restore"))
        #expect(!response.ok)
        #expect(response.error == "Missing project name")
    }

    @Test func projectRestoreNonexistentFails() {
        let response = router.dispatch(TestCommand.make("project.restore", args: ["name": "_test_nonexistent_xyz"]))
        #expect(!response.ok)
    }

    // MARK: - project.delete

    @Test func projectDeleteMissingNameFails() {
        let response = router.dispatch(TestCommand.make("project.delete"))
        #expect(!response.ok)
        #expect(response.error == "Missing project name")
    }

    // MARK: - project.rename

    @Test func projectRenameMissingArgsFails() {
        let response = router.dispatch(TestCommand.make("project.rename"))
        #expect(!response.ok)
        #expect(response.error == "Missing name or new_name")
    }

    @Test func projectRenameMissingNewNameFails() {
        let response = router.dispatch(TestCommand.make("project.rename", args: ["name": "foo"]))
        #expect(!response.ok)
        #expect(response.error == "Missing name or new_name")
    }

    @Test func projectRenameMissingNameFails() {
        let response = router.dispatch(TestCommand.make("project.rename", args: ["new_name": "bar"]))
        #expect(!response.ok)
        #expect(response.error == "Missing name or new_name")
    }

    // MARK: - project.switch

    @Test func projectSwitchMissingNameFails() {
        let response = router.dispatch(TestCommand.make("project.switch"))
        #expect(!response.ok)
        #expect(response.error == "Missing project name")
    }

    // MARK: - project.close-all

    @Test func projectCloseAllSucceedsEmpty() {
        let response = router.dispatch(TestCommand.make("project.close-all"))
        #expect(response.ok)
    }

    // MARK: - workspace.new

    @Test func workspaceNewMissingNameFails() {
        let response = router.dispatch(TestCommand.make("workspace.new"))
        #expect(!response.ok)
        #expect(response.error == "Missing workspace name")
    }

    @Test func workspaceNewEmptyNameFails() {
        let response = router.dispatch(TestCommand.make("workspace.new", args: ["name": ""]))
        #expect(!response.ok)
        #expect(response.error == "Missing workspace name")
    }

    // MARK: - workspace.switch

    @Test func workspaceSwitchMissingNameFails() {
        let response = router.dispatch(TestCommand.make("workspace.switch"))
        #expect(!response.ok)
        #expect(response.error == "Missing workspace name")
    }

    @Test func workspaceSwitchNonexistentFails() {
        let response = router.dispatch(TestCommand.make("workspace.switch", args: ["name": "_nonexistent_ws"]))
        #expect(!response.ok)
        #expect(response.error == "Workspace not found: _nonexistent_ws")
    }

    // MARK: - workspace.rename

    @Test func workspaceRenameMissingArgsFails() {
        let response = router.dispatch(TestCommand.make("workspace.rename"))
        #expect(!response.ok)
        #expect(response.error == "Missing name or new_name")
    }

    @Test func workspaceRenameMissingNewNameFails() {
        let response = router.dispatch(TestCommand.make("workspace.rename", args: ["name": "foo"]))
        #expect(!response.ok)
        #expect(response.error == "Missing name or new_name")
    }

    // MARK: - workspace.remove

    @Test func workspaceRemoveMissingNameFails() {
        let response = router.dispatch(TestCommand.make("workspace.remove"))
        #expect(!response.ok)
        #expect(response.error == "Missing workspace name")
    }

    @Test func workspaceRemoveNonexistentFails() {
        let response = router.dispatch(TestCommand.make("workspace.remove", args: ["name": "_nonexistent_ws"]))
        #expect(!response.ok)
        #expect(response.error == "Workspace not found: _nonexistent_ws")
    }

    // MARK: - workspace.list

    @Test func workspaceListSucceeds() {
        let response = router.dispatch(TestCommand.make("workspace.list"))
        #expect(response.ok)
    }

    // MARK: - workspace.next / previous / move

    @Test func workspaceNextSucceeds() {
        let response = router.dispatch(TestCommand.make("workspace.next"))
        #expect(response.ok)
    }

    @Test func workspacePreviousSucceeds() {
        let response = router.dispatch(TestCommand.make("workspace.previous"))
        #expect(response.ok)
    }

    @Test func workspaceMoveNextSucceeds() {
        let response = router.dispatch(TestCommand.make("workspace.move-next"))
        #expect(response.ok)
    }

    @Test func workspaceMovePreviousSucceeds() {
        let response = router.dispatch(TestCommand.make("workspace.move-previous"))
        #expect(response.ok)
    }

    // MARK: - workspace.break-pane

    @Test func workspaceBreakPaneSucceeds() {
        let response = router.dispatch(TestCommand.make("workspace.break-pane"))
        #expect(response.ok)
    }

    // MARK: - workspace.meta.set

    @Test func workspaceMetaSetMissingArgsFails() {
        let response = router.dispatch(TestCommand.make("workspace.meta.set"))
        #expect(!response.ok)
        #expect(response.error == "Missing workspace, key, or value")
    }

    @Test func workspaceMetaSetPartialArgsFails() {
        let response = router.dispatch(TestCommand.make("workspace.meta.set", args: ["workspace": "ws"]))
        #expect(!response.ok)
        #expect(response.error == "Missing workspace, key, or value")
    }

    // MARK: - workspace.meta.clear

    @Test func workspaceMetaClearMissingArgsFails() {
        let response = router.dispatch(TestCommand.make("workspace.meta.clear"))
        #expect(!response.ok)
        #expect(response.error == "Missing workspace or key")
    }
}
