import Testing
@testable import GhosttyIDE

struct SessionCommandTests {
    private let router = IDECommandRouter()

    // MARK: - session.info

    @Test func sessionInfoReturnsData() {
        let response = router.dispatch(TestCommand.make("session.info"))
        #expect(response.ok)
        #expect(response.dataDict != nil)
        if let data = response.dataDict {
            // Should always have "exists" field
            #expect(data["exists"] != nil)
        }
    }

    // MARK: - session.save

    @Test func sessionSaveSucceeds() {
        let response = router.dispatch(TestCommand.make("session.save"))
        #expect(response.ok)
    }
}
