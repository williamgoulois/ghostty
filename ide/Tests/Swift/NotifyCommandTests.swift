import Testing
@testable import GhosttyIDE

struct NotifyCommandTests {
    private let router = IDECommandRouter()

    // MARK: - notify.send

    @Test func sendMissingTitleFails() {
        let response = router.dispatch(TestCommand.make("notify.send"))
        #expect(!response.ok)
        #expect(response.error == "Missing 'title' argument")
    }

    @Test func sendEmptyTitleFails() {
        let response = router.dispatch(TestCommand.make("notify.send", args: ["title": ""]))
        #expect(!response.ok)
        #expect(response.error == "Missing 'title' argument")
    }

    // MARK: - notify.list

    @Test func listReturnsData() {
        let response = router.dispatch(TestCommand.make("notify.list"))
        #expect(response.ok)
        #expect(response.dataDict != nil)
    }

    // MARK: - notify.clear

    @Test func clearSucceeds() {
        let response = router.dispatch(TestCommand.make("notify.clear"))
        #expect(response.ok)
    }

    // MARK: - notify.status

    @Test func statusReturnsData() {
        let response = router.dispatch(TestCommand.make("notify.status"))
        #expect(response.ok)
        if let data = response.dataDict {
            #expect(data["unread_count"] != nil)
        } else {
            Issue.record("Expected data in notify.status response")
        }
    }
}
