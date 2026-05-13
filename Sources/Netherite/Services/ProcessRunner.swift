import Foundation

struct CommandResult {
    let output: String
    let exitCode: Int32
}

enum ProcessRunnerError: LocalizedError {
    case failed(command: [String], result: CommandResult)

    var errorDescription: String? {
        switch self {
        case let .failed(command, result):
            let renderedCommand = command.joined(separator: " ")
            let output = result.output.trimmed
            if output.isEmpty {
                return "\(renderedCommand) exited with code \(result.exitCode)."
            }
            return "\(renderedCommand) exited with code \(result.exitCode):\n\(output)"
        }
    }
}

enum ProcessRunner {
    @discardableResult
    static func run(
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, next in next }
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: data, as: UTF8.self)
        let result = CommandResult(output: output, exitCode: process.terminationStatus)
        guard process.terminationStatus == 0 else {
            throw ProcessRunnerError.failed(command: arguments, result: result)
        }
        return result
    }
}
