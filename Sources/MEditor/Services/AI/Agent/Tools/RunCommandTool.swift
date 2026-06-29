import Foundation

// MARK: - Run Command

/// 执行 shell 命令（主要用于"脚本型" skill，如运行 SKILL 目录下的 scripts/*.ts）。
/// 安全：执行前必须经用户在 agent step 流里确认（会话级授权，首次确认后本会话不再询问）。
struct RunCommandTool: AgentTool {
    let spec = AgentToolSpec(
        name: "run_command",
        description: "Run a shell command (for script-based skills, e.g. `npx tsx <SKILL_DIR>/scripts/publish.ts ...`). The user must confirm execution in the step flow before it runs. Use the skill's real SKILL_DIR for paths and pass it as 'cwd'. Returns the command's combined stdout/stderr.",
        parameters: ToolParameterSchema(
            properties: [
                "command": ToolPropertySchema(type: "string", description: "The exact shell command to run."),
                "cwd":     ToolPropertySchema(type: "string", description: "Working directory (use the skill's SKILL_DIR when running a skill's script). Optional; defaults to the workspace root.")
            ],
            required: ["command"]
        )
    )

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        guard let command = arguments["command"]?.stringValue, !command.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AgentError.executionError("缺少 command 参数")
        }
        let cwd = arguments["cwd"]?.stringValue
        let resolvedCwd = (cwd?.isEmpty == false) ? cwd : await context.workspaceURL?.path

        // 执行前确认（会话级授权）
        let approved = await context.confirmCommandExecution(command, cwd: resolvedCwd)
        guard approved else { return "[!] 用户已拒绝执行该命令：\(command)" }

        return await Self.runViaLoginShell(command: command, cwd: resolvedCwd)
    }

    /// 通过 login shell 执行命令（加载 .zshrc/.zprofile 以获得 PATH，能跑 npx/node 等），合并 stdout/stderr。
    private static func runViaLoginShell(command: String, cwd: String?) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-l", "-c", command]
            if let cwd, !cwd.isEmpty {
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
            }
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = outPipe   // 合并 stderr 到同一管道
            do {
                try process.run()
            } catch {
                return "[X] 无法启动命令：\(error.localizedDescription)"
            }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            var output = String(data: data, encoding: .utf8) ?? ""
            // 截断超长输出，避免撑爆上下文
            let maxBytes = 16_000
            if output.utf8.count > maxBytes {
                output = String(output.prefix(maxBytes)) + "\n…（输出过长已截断）"
            }
            let status = process.terminationStatus
            let header = status == 0 ? "[OK] 命令完成（exit 0）" : "[!] 命令退出码 \(status)"
            return "\(header)\n$ \(command)\n\n\(output.isEmpty ? "(无输出)" : output)"
        }.value
    }
}
