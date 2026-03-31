import Testing
@testable import GhosttyIDE

struct ProcessCommandTests {
    private let router = IDECommandRouter()

    // MARK: - process.kill

    @Test func killMissingPidFails() {
        let response = router.dispatch(TestCommand.make("process.kill"))
        #expect(!response.ok)
        #expect(response.error == "Missing or invalid 'pid' argument")
    }

    @Test func killInvalidPidFails() {
        let response = router.dispatch(TestCommand.make("process.kill", args: ["pid": -1]))
        #expect(!response.ok)
        #expect(response.error == "Missing or invalid 'pid' argument")
    }

    @Test func killNonexistentPidFails() {
        let response = router.dispatch(TestCommand.make("process.kill", args: ["pid": 99999]))
        #expect(!response.ok)
        #expect(response.error?.contains("not found") == true)
    }

    // MARK: - port.list

    @Test func portListReturnsData() {
        let response = router.dispatch(TestCommand.make("port.list"))
        #expect(response.ok)
        #expect(response.dataDict?["ports"] is [[String: Any]])
    }

    @Test func portListFilteredByWorkspace() {
        let response = router.dispatch(TestCommand.make("port.list", args: ["workspace": "nonexistent"]))
        #expect(response.ok)
        if let ports = response.dataDict?["ports"] as? [[String: Any]] {
            #expect(ports.isEmpty)
        }
    }
}
