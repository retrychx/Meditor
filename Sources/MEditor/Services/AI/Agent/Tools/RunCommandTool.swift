import Foundation

// MARK: - RunCommandTool

/// 执行 shell 命令（主要用于"脚本型" skill，如运行 SKILL 目录下的 scripts/*.ts）。
///
/// ## 安全机制（多层防御）
///
/// 1. **静态风险分析**（CommandSandbox.assess）
///    - `.blocked`：直接拒绝，不弹确认框（如 rm -rf /、sudo、curl 等）
///    - `.warn`：高风险，每次都弹确认框，不复用缓存
///    - `.safe`：低风险，命中 per-key 缓存时跳过弹框
///
/// 2. **工作目录限制**（CommandSandbox.validateCwd）
///    - cwd 必须在当前工作区根目录内
///    - 检测路径穿越（../）
///    - 没有打开工作区时不限制
///
/// 3. **Skill 白名单**（allowedCommandPatterns）
///    - Skill 可在 SKILL.md 的 `allowedCommands:` 字段声明允许的命令前缀
///    - 不在白名单内的命令直接拒绝，不弹确认框
///
/// 4. **Per-command-key 确认缓存**
///    - 相同命令 + cwd 组合，用户确认一次后本次 agent session 内不再弹框
///    - warn 级别命令不复用缓存，每次都要确认
///
/// 5. **执行超时**
///    - 单条命令最长执行 `executionTimeoutSeconds`（默认 30s）
///    - 超时后进程被强制终止，返回错误信息
///
/// 6. **输出截断**
///    - stdout + stderr 合并后超过 `maxOutputBytes` 时截断（默认 16KB）
///
struct RunCommandTool: AgentTool {

    // MARK: - Configuration

    /// 单条命令最长执行时间（秒）。超时后进程被强制终止。
    var executionTimeoutSeconds: TimeInterval = 30

    /// 最大输出字节数（超出后截断，避免撑爆上下文）。
    var maxOutputBytes: Int = 16_000

    // MARK: - Spec

    let spec = AgentToolSpec(
        name: "run_command",
        description: """
        Run a shell command (for script-based skills, e.g. `npx tsx <SKILL_DIR>/scripts/publish.ts`). \
        Requires user confirmation before execution. \
        Blocked commands (rm -rf, sudo, curl, etc.) are rejected automatically. \
        The cwd must be inside the current workspace. \
        Returns the command's combined stdout/stderr (max 16 KB).
        """,
        parameters: ToolParameterSchema(
            properties: [
                "command": ToolPropertySchema(
                    type: "string",
                    description: "The exact shell command to run."
                ),
                "cwd": ToolPropertySchema(
                    type: "string",
                    description: "Working directory. Must be inside the workspace root. Defaults to the workspace root."
                ),
            ],
            required: ["command"]
        )
    )

    // MARK: - Execute

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        // 1. 参数提取
        guard let command = arguments["command"]?.stringValue,
              !command.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AgentError.executionError("缺少 command 参数")
        }

        let rawCwd = arguments["cwd"]?.stringValue
        let workspaceRoot = await context.workspaceURL?.path
        let resolvedCwd: String

        // 2. 工作目录校验
        let cwdToValidate = (rawCwd?.isEmpty == false) ? rawCwd! : (workspaceRoot ?? "")
        let cwdValidation = CommandSandbox.validateCwd(cwdToValidate, workspaceRoot: workspaceRoot)
        switch cwdValidation {
        case .allowed(let resolved):
            resolvedCwd = resolved.isEmpty ? (workspaceRoot ?? "") : resolved
        case .outsideWorkspace, .traversalDetected:
            return "[!] \(cwdValidation.errorMessage ?? "工作目录校验失败")"
        }

        // 3. 静态风险评估
        let risk = CommandSandbox.assess(command)
        if case .blocked(let reason) = risk {
            return "[!] \(reason)"
        }

        // 4. Skill 白名单校验
        let patterns = await context.allowedCommandPatterns
        if !CommandSandbox.matchesAllowedPatterns(command, patterns: patterns) {
            let list = patterns?.prefix(5).joined(separator: ", ") ?? ""
            return "[!] 安全限制：当前 Skill 未声明允许执行此命令。\n允许的命令前缀：\(list)\n命令：\(command)"
        }

        // 5. 用户确认（warn 级别不复用缓存；safe 级别复用）
        let approvalKey = CommandSandbox.approvalKey(command: command, cwd: resolvedCwd.isEmpty ? nil : resolvedCwd)
        let isWarn = { if case .warn = risk { return true }; return false }()

        let needsDialog: Bool
        if isWarn {
            // warn 命令：每次都弹确认
            needsDialog = true
        } else {
            // safe 命令：检查 per-key 缓存
            needsDialog = !(await context.isCommandApproved(approvalKey))
        }

        if needsDialog {
            let approved = await context.confirmCommandExecution(command, cwd: resolvedCwd.isEmpty ? nil : resolvedCwd)
            guard approved else {
                return "[!] 用户已拒绝执行该命令：\(command)"
            }
            // 只有 safe 命令才缓存审批
            if !isWarn {
                await context.markCommandApproved(approvalKey)
            }
        }

        // 6. 执行命令（with timeout）
        return await runWithTimeout(command: command, cwd: resolvedCwd.isEmpty ? nil : resolvedCwd)
    }

    // MARK: - Execution

    /// 共享的 Process 引用，让超时/取消分支能够触达 detached 任务里的子进程。
    private final class ProcessBox: @unchecked Sendable { var process: Process? }

    /// 执行命令，带超时保护。超时或外层取消时会真正终止子进程。
    private func runWithTimeout(command: String, cwd: String?) async -> String {
        let timeout = executionTimeoutSeconds
        let maxBytes = maxOutputBytes
        let box = ProcessBox()

        return await withTaskCancellationHandler {
            await withTaskGroup(of: String.self) { group in
                // 实际执行任务
                group.addTask {
                    await Self.runViaLoginShell(command: command, cwd: cwd, maxOutputBytes: maxBytes, box: box)
                }
                // 超时哨兵
                group.addTask {
                    do {
                        try await Task.sleep(for: .seconds(timeout))
                    } catch {
                        // 被 cancel（主任务完成），不触发超时
                        return "__CANCELLED__"
                    }
                    return "__TIMEOUT__"
                }

                // 取第一个完成的结果
                var result = ""
                for await value in group {
                    group.cancelAll()
                    if value == "__CANCELLED__" { continue }
                    if value == "__TIMEOUT__" {
                        // 真正终止子进程：SIGTERM 关闭管道，解除 runViaLoginShell 的阻塞
                        box.process?.terminate()
                        result = "[!] 命令执行超时（\(Int(timeout))s），进程已终止。\n命令：\(command)"
                    } else {
                        result = value
                    }
                    break
                }
                return result
            }
        } onCancel: {
            box.process?.terminate()
        }
    }

    /// 通过 login shell 执行命令，确保 PATH / nvm / rbenv 等环境变量可用。
    /// stdout 与 stderr 合并到同一管道，超限截断。
    /// 启动成功后的 Process 会写入 `box`，供超时/取消路径 terminate。
    private static func runViaLoginShell(command: String, cwd: String?, maxOutputBytes: Int, box: ProcessBox) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            // 加 -l -i：GUI 进程的环境变量是登录时的一份静态快照，不会加载用户的
            // .zshrc/.zprofile/.bash_profile；nvm/pyenv/rbenv 等工具链通常只在这些
            // rc 文件里配置 PATH，缺少 -l -i 会导致 Agent 执行命令时找不到用户实际
            // 在交互式终端里能用的工具版本（曾错误地为"避免慢启动/意外 cd"去掉过，
            // 但代价是牺牲了 PATH 正确性，收益不对等，这里改回来）。
            process.arguments = ["-l", "-i", "-c", command]
            process.environment = ProcessInfo.processInfo.environment

            if let cwd, !cwd.isEmpty {
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = pipe   // 合并 stderr

            do {
                try process.run()
            } catch {
                return "[X] 无法启动命令：\(error.localizedDescription)\n命令：\(command)"
            }
            box.process = process

            // 边读边截：超限后继续 drain 管道（避免子进程因管道满而阻塞），
            // 但不再累积，防止超大输出先把内存撑爆。
            var data = Data()
            var wasTruncated = false
            let handle = pipe.fileHandleForReading
            while true {
                let chunk = handle.readData(ofLength: 8192)
                if chunk.isEmpty { break }   // EOF
                let remaining = maxOutputBytes - data.count
                if remaining > 0 {
                    data.append(chunk.prefix(remaining))
                    if chunk.count > remaining { wasTruncated = true }
                } else {
                    wasTruncated = true
                }
            }
            process.waitUntilExit()

            var output = TextFileDecoder.decode(data) ?? ""
            if wasTruncated {
                output += "\n…（输出过长，已截断到 \(maxOutputBytes / 1000)KB）"
            }

            let status = process.terminationStatus
            let header = status == 0
                ? "[OK] 命令完成（exit 0）"
                : "[!] 命令退出码 \(status)"

            return "\(header)\n$ \(command)\n\n\(output.isEmpty ? "（无输出）" : output)"
        }.value
    }
}
