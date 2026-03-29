import Testing
@testable import GhosttyIDE

struct PaneCommandTests {
    private let router = IDECommandRouter()

    // MARK: - pane.list

    @Test func listReturnsEmptyPanes() {
        let response = router.dispatch(TestCommand.make("pane.list"))
        #expect(response.ok)
        if let panes = response.dataDict?["panes"] as? [Any] {
            #expect(panes.isEmpty)
        } else {
            Issue.record("Expected panes array in response")
        }
    }

    @Test func listWithProjectFilterReturnsEmpty() {
        let response = router.dispatch(TestCommand.make("pane.list", args: ["project": "nonexistent"]))
        #expect(response.ok)
        if let panes = response.dataDict?["panes"] as? [Any] {
            #expect(panes.isEmpty)
        }
    }

    @Test func listWithWorkspaceFilterReturnsEmpty() {
        let response = router.dispatch(TestCommand.make("pane.list", args: ["workspace": "nonexistent"]))
        #expect(response.ok)
        if let panes = response.dataDict?["panes"] as? [Any] {
            #expect(panes.isEmpty)
        }
    }

    // MARK: - pane.focus

    @Test func focusMissingIdFails() {
        let response = router.dispatch(TestCommand.make("pane.focus"))
        #expect(!response.ok)
        #expect(response.error == "Missing or invalid 'id' argument")
    }

    @Test func focusInvalidUUIDFails() {
        let response = router.dispatch(TestCommand.make("pane.focus", args: ["id": "not-a-uuid"]))
        #expect(!response.ok)
        #expect(response.error == "Missing or invalid 'id' argument")
    }

    @Test func focusNonexistentPaneFails() {
        let uuid = UUID().uuidString
        let response = router.dispatch(TestCommand.make("pane.focus", args: ["id": uuid]))
        #expect(!response.ok)
        #expect(response.error == "Pane not found: \(uuid)")
    }

    // MARK: - pane.focus-direction

    @Test func focusDirectionMissingFails() {
        let response = router.dispatch(TestCommand.make("pane.focus-direction"))
        #expect(!response.ok)
        #expect(response.error?.contains("Missing 'direction'") == true)
    }

    @Test func focusDirectionEmptyFails() {
        let response = router.dispatch(TestCommand.make("pane.focus-direction", args: ["direction": ""]))
        #expect(!response.ok)
        #expect(response.error?.contains("Missing 'direction'") == true)
    }

    @Test func focusDirectionInvalidFails() {
        let response = router.dispatch(TestCommand.make("pane.focus-direction", args: ["direction": "diagonal"]))
        #expect(!response.ok)
        #expect(response.error?.contains("Invalid direction") == true)
    }

    @Test(arguments: ["left", "right", "up", "down"])
    func focusDirectionValidButNoSurface(direction: String) {
        let response = router.dispatch(TestCommand.make("pane.focus-direction", args: ["direction": direction]))
        #expect(!response.ok)
        #expect(response.error == "No active terminal surface")
    }

    // MARK: - pane.split

    @Test func splitInvalidDirectionFails() {
        let response = router.dispatch(TestCommand.make("pane.split", args: ["direction": "diagonal"]))
        #expect(!response.ok)
        #expect(response.error?.contains("Invalid direction") == true)
    }

    @Test func splitNoSurfaceFails() {
        // Default direction "right" but no focused surface
        let response = router.dispatch(TestCommand.make("pane.split"))
        #expect(!response.ok)
        #expect(response.error == "No active terminal surface")
    }

    @Test(arguments: ["left", "right", "up", "down"])
    func splitValidDirectionNoSurface(direction: String) {
        let response = router.dispatch(TestCommand.make("pane.split", args: ["direction": direction]))
        #expect(!response.ok)
        #expect(response.error == "No active terminal surface")
    }

    // MARK: - pane.close

    @Test func closeMissingIdFails() {
        let response = router.dispatch(TestCommand.make("pane.close"))
        #expect(!response.ok)
        #expect(response.error == "Missing or invalid 'id' argument")
    }

    @Test func closeInvalidUUIDFails() {
        let response = router.dispatch(TestCommand.make("pane.close", args: ["id": "bad"]))
        #expect(!response.ok)
        #expect(response.error == "Missing or invalid 'id' argument")
    }

    @Test func closeNonexistentPaneFails() {
        let uuid = UUID().uuidString
        let response = router.dispatch(TestCommand.make("pane.close", args: ["id": uuid]))
        #expect(!response.ok)
        #expect(response.error == "Pane not found: \(uuid)")
    }

    // MARK: - pane.send-text

    @Test func sendTextMissingIdFails() {
        let response = router.dispatch(TestCommand.make("pane.send-text", args: ["text": "hello"]))
        #expect(!response.ok)
        #expect(response.error == "Missing or invalid 'id' argument")
    }

    @Test func sendTextInvalidIdFails() {
        let response = router.dispatch(TestCommand.make("pane.send-text", args: ["id": "bad", "text": "hello"]))
        #expect(!response.ok)
        #expect(response.error == "Missing or invalid 'id' argument")
    }

    @Test func sendTextMissingTextFails() {
        let uuid = UUID().uuidString
        let response = router.dispatch(TestCommand.make("pane.send-text", args: ["id": uuid]))
        #expect(!response.ok)
        #expect(response.error == "Missing or empty 'text' argument")
    }

    @Test func sendTextEmptyTextFails() {
        let uuid = UUID().uuidString
        let response = router.dispatch(TestCommand.make("pane.send-text", args: ["id": uuid, "text": ""]))
        #expect(!response.ok)
        #expect(response.error == "Missing or empty 'text' argument")
    }

    @Test func sendTextNonexistentPaneFails() {
        let uuid = UUID().uuidString
        let response = router.dispatch(TestCommand.make("pane.send-text", args: ["id": uuid, "text": "hello"]))
        #expect(!response.ok)
        #expect(response.error == "Pane not found: \(uuid)")
    }
}
