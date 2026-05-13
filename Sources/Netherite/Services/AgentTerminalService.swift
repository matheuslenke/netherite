import Foundation

enum AgentTool: String, CaseIterable, Identifiable {
    case terminal
    case codex
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal:
            "Terminal"
        case .codex:
            "Codex"
        case .claude:
            "Claude Code"
        }
    }

    var executable: String? {
        switch self {
        case .terminal:
            nil
        case .codex:
            "codex"
        case .claude:
            "claude"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal:
            "terminal"
        case .codex:
            "sparkles"
        case .claude:
            "text.bubble"
        }
    }
}

final class AgentTerminalService {
    func availability() -> [AgentTool: Bool] {
        var result: [AgentTool: Bool] = [:]
        for tool in AgentTool.allCases {
            guard let executable = tool.executable else {
                result[tool] = true
                continue
            }
            result[tool] = (try? ProcessRunner.run(arguments: ["which", executable])) != nil
        }
        return result
    }

    func open(tool: AgentTool, vaultURL: URL, file: VaultFile?, prompt: String) throws {
        let command = shellCommand(tool: tool, vaultURL: vaultURL, file: file, prompt: prompt)
        let script = """
        tell application "Terminal"
          activate
          do script "\(command.appleScriptQuoted())"
        end tell
        """
        try ProcessRunner.run(arguments: ["osascript", "-e", script])
    }

    private func shellCommand(tool: AgentTool, vaultURL: URL, file: VaultFile?, prompt: String) -> String {
        let cd = "cd \(vaultURL.path.shellQuoted())"
        guard let executable = tool.executable else { return cd }

        let target = file?.relativePath ?? "the vault"
        let defaultPrompt = "Use this vault as context and help improve \(target)."
        let resolvedPrompt = prompt.trimmed.isEmpty ? defaultPrompt : prompt.trimmed
        return "\(cd) && \(executable) \(resolvedPrompt.shellQuoted())"
    }
}
