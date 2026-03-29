import Testing
@testable import GhosttyIDE

struct StatusCommandTests {
    private let router = IDECommandRouter()

    // MARK: - status.set

    @Test func setMissingKeyFails() {
        let response = router.dispatch(TestCommand.make("status.set"))
        #expect(!response.ok)
        #expect(response.error == "Missing 'key' argument")
    }

    @Test func setMissingValueFails() {
        let response = router.dispatch(TestCommand.make("status.set", args: ["key": "branch"]))
        #expect(!response.ok)
        #expect(response.error == "Missing 'value' argument")
    }

    @Test func setNoPaneIdAndNoFocusedPaneFails() {
        let response = router.dispatch(TestCommand.make("status.set", args: [
            "key": "branch",
            "value": "main",
        ]))
        #expect(!response.ok)
        #expect(response.error == "No pane_id provided and no focused pane")
    }

    // MARK: - status.list

    @Test func listReturnsData() {
        let response = router.dispatch(TestCommand.make("status.list"))
        #expect(response.ok)
    }

    // MARK: - status.clear

    @Test func clearSucceeds() {
        let response = router.dispatch(TestCommand.make("status.clear"))
        #expect(response.ok)
    }
}
