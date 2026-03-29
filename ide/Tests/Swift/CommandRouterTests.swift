import Testing
@testable import GhosttyIDE

struct CommandRouterTests {

    // MARK: - Registration

    @Test func registersAllExpectedCommands() {
        let router = IDECommandRouter()
        // 31 commands total across all register*Commands() calls
        #expect(router.handlers.count >= 30)
    }

    // MARK: - Dispatch

    @Test func unknownCommandReturnsFailure() {
        let router = IDECommandRouter()
        let cmd = TestCommand.make("nonexistent.command")
        let response = router.dispatch(cmd)
        #expect(!response.ok)
        #expect(response.error == "Unknown command: nonexistent.command")
    }

    @Test func emptyCommandNameReturnsFailure() {
        let router = IDECommandRouter()
        let cmd = TestCommand.make("")
        let response = router.dispatch(cmd)
        #expect(!response.ok)
    }

    // MARK: - help

    @Test func helpReturnsAllCommandsSorted() {
        let router = IDECommandRouter()
        let response = router.dispatch(TestCommand.make("help"))
        #expect(response.ok)
        if let commands = response.dataDict?["commands"] as? [String] {
            #expect(commands == commands.sorted())
            #expect(commands.count == router.handlers.count)
            #expect(commands.contains("pane.list"))
            #expect(commands.contains("pane.send-text"))
            #expect(commands.contains("workspace.new"))
            #expect(commands.contains("session.save"))
        } else {
            Issue.record("Expected sorted commands array in help response")
        }
    }

    // MARK: - app.pid

    @Test func appPidReturnsCurrentProcess() {
        let router = IDECommandRouter()
        let response = router.dispatch(TestCommand.make("app.pid"))
        #expect(response.ok)
        if let pid = response.dataDict?["pid"] as? Int {
            #expect(pid == Int(ProcessInfo.processInfo.processIdentifier))
        } else {
            Issue.record("Expected pid in response data")
        }
    }

    // MARK: - app.version

    @Test func appVersionReturnsData() {
        let router = IDECommandRouter()
        let response = router.dispatch(TestCommand.make("app.version"))
        #expect(response.ok)
        #expect(response.dataDict != nil)
    }
}
