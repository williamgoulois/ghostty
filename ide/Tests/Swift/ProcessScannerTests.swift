import Testing
@testable import GhosttyIDE

struct ProcessScannerTests {

    // MARK: - Classification

    @Test func classifyAgentProcesses() {
        #expect(ProcessScanner.classify("claude") == .agent)
        #expect(ProcessScanner.classify("opencode") == .agent)
    }

    @Test func classifyAgentCaseInsensitive() {
        #expect(ProcessScanner.classify("Claude") == .agent)
        #expect(ProcessScanner.classify("OPENCODE") == .agent)
    }

    @Test func classifyShellProcesses() {
        #expect(ProcessScanner.classify("zsh") == .shell)
        #expect(ProcessScanner.classify("bash") == .shell)
        #expect(ProcessScanner.classify("fish") == .shell)
        #expect(ProcessScanner.classify("sh") == .shell)
        #expect(ProcessScanner.classify("dash") == .shell)
        #expect(ProcessScanner.classify("nu") == .shell)
        #expect(ProcessScanner.classify("login") == .shell)
    }

    @Test func classifyEditorProcesses() {
        #expect(ProcessScanner.classify("vim") == .editor)
        #expect(ProcessScanner.classify("nvim") == .editor)
        #expect(ProcessScanner.classify("vi") == .editor)
        #expect(ProcessScanner.classify("gvim") == .editor)
        #expect(ProcessScanner.classify("emacs") == .editor)
        #expect(ProcessScanner.classify("vimdiff") == .editor)
    }

    @Test func classifyLongRunningProcesses() {
        #expect(ProcessScanner.classify("node") == .longRunning)
        #expect(ProcessScanner.classify("cargo") == .longRunning)
        #expect(ProcessScanner.classify("python3") == .longRunning)
        #expect(ProcessScanner.classify("npm") == .longRunning)
        #expect(ProcessScanner.classify("make") == .longRunning)
        #expect(ProcessScanner.classify("ruby") == .longRunning)
    }

    @Test func classifyUnknownFallsToLongRunning() {
        // Unknown processes are classified as longRunning (not shell/agent/editor)
        #expect(ProcessScanner.classify("my-custom-tool") == .longRunning)
        #expect(ProcessScanner.classify("webpack-dev-server") == .longRunning)
    }
}
