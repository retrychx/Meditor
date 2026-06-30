import XCTest
@testable import MEditor

// MARK: - IntentClassifierTests
//
// 验证 ClaudeCLIBackend 的 IntentScorer 评分逻辑，
// 通过白盒访问静态方法测试各类边界输入。

final class IntentClassifierTests: XCTestCase {

    // MARK: - Command Intent（得分 >= threshold）

    func test_runCommand_isCommandIntent() {
        XCTAssertGreaterThanOrEqual(
            commandScore("please run command git status"),
            ClaudeCLIBackend.IntentScorer.threshold,
            "\"run command\" 应触发 command 意图"
        )
    }

    func test_runScript_isCommandIntent() {
        XCTAssertGreaterThanOrEqual(
            commandScore("run script ./deploy.sh"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    func test_executeCommand_isCommandIntent() {
        XCTAssertGreaterThanOrEqual(
            commandScore("execute command npm install"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    func test_npx_isCommandIntent() {
        XCTAssertGreaterThanOrEqual(
            commandScore("use npx tsx scripts/gen.ts to generate"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    func test_chineseRunCommand_isCommandIntent() {
        XCTAssertGreaterThanOrEqual(
            commandScore("帮我运行命令 git log"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    func test_chineseExecuteScript_isCommandIntent() {
        XCTAssertGreaterThanOrEqual(
            commandScore("执行脚本 build.sh"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    // MARK: - Command Intent 否定词（应被抑制）

    func test_runtime_doesNotTriggerCommandIntent() {
        // "runtime" 不应触发 command 意图（旧 bug）
        XCTAssertLessThan(
            commandScore("what is the node runtime version"),
            ClaudeCLIBackend.IntentScorer.threshold,
            "\"runtime\" 不应误触 command 意图"
        )
    }

    func test_runThrough_doesNotTriggerCommandIntent() {
        XCTAssertLessThan(
            commandScore("let me run through the plan with you"),
            ClaudeCLIBackend.IntentScorer.threshold,
            "\"run through\" 不应误触 command 意图"
        )
    }

    func test_runDown_doesNotTriggerCommandIntent() {
        XCTAssertLessThan(
            commandScore("run down the list of issues"),
            ClaudeCLIBackend.IntentScorer.threshold,
            "\"run down\" 不应误触 command 意图"
        )
    }

    func test_makeItWork_doesNotTriggerCommandIntent() {
        // "make" 单独出现但 "make sure" / "make it" 在否定词列表中
        XCTAssertLessThan(
            commandScore("make sure the tests pass"),
            ClaudeCLIBackend.IntentScorer.threshold,
            "\"make sure\" 不应误触 command 意图"
        )
    }

    func test_dontRunCommand_doesNotTriggerCommandIntent() {
        XCTAssertLessThan(
            commandScore("don't run command, just explain"),
            ClaudeCLIBackend.IntentScorer.threshold,
            "\"don't run command\" 的否定语境应被抑制"
        )
    }

    // MARK: - FileManage Intent

    func test_createFile_isFileManageIntent() {
        XCTAssertGreaterThanOrEqual(
            fileManageScore("please create file README.md"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    func test_newFile_isFileManageIntent() {
        XCTAssertGreaterThanOrEqual(
            fileManageScore("create a new file called config.ts"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    func test_mkdir_isFileManageIntent() {
        XCTAssertGreaterThanOrEqual(
            fileManageScore("mkdir src/components"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    func test_chineseCreateFile_isFileManageIntent() {
        XCTAssertGreaterThanOrEqual(
            fileManageScore("帮我新建文件 utils.ts"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    func test_chineseCreateDirectory_isFileManageIntent() {
        XCTAssertGreaterThanOrEqual(
            fileManageScore("创建目录 src/api"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    // MARK: - Mixed Intent（得分 < threshold，不确定）

    func test_generic_analysis_isMixed() {
        XCTAssertLessThan(
            commandScore("analyze this code and explain what it does"),
            ClaudeCLIBackend.IntentScorer.threshold,
            "通用分析请求应是 mixed 意图"
        )
    }

    func test_refactor_isMixed() {
        XCTAssertLessThan(
            commandScore("refactor this function to be more readable"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    func test_translate_isMixed() {
        XCTAssertLessThan(
            commandScore("translate this paragraph to English"),
            ClaudeCLIBackend.IntentScorer.threshold
        )
    }

    func test_emptyMessage_isMixed() {
        XCTAssertLessThan(commandScore(""), ClaudeCLIBackend.IntentScorer.threshold)
        XCTAssertLessThan(fileManageScore(""), ClaudeCLIBackend.IntentScorer.threshold)
    }

    // MARK: - Score Ordering（命令明确性 > 模糊）

    func test_explicitCommandPhrase_higherScoreThanVague() {
        let explicitScore = commandScore("execute command npm test")
        let vagueScore    = commandScore("maybe script something")
        XCTAssertGreaterThan(explicitScore, vagueScore,
                             "明确的命令短语应得分高于模糊描述")
    }

    // MARK: - Threshold Stability

    func test_threshold_isAtLeast2() {
        // 确保阈值不会被意外改低（太低会导致误分类）
        XCTAssertGreaterThanOrEqual(ClaudeCLIBackend.IntentScorer.threshold, 2,
                                    "阈值不应低于 2，否则容易误触发")
    }

    // MARK: - Helpers

    /// 计算字符串对 commandPhrases 的总得分
    private func commandScore(_ text: String) -> Int {
        ClaudeCLIBackend.IntentScorer.score(text: text.lowercased(),
                                             phrases: ClaudeCLIBackend.IntentScorer.commandPhrases)
    }

    /// 计算字符串对 fileManagePhrases 的总得分
    private func fileManageScore(_ text: String) -> Int {
        ClaudeCLIBackend.IntentScorer.score(text: text.lowercased(),
                                             phrases: ClaudeCLIBackend.IntentScorer.fileManagePhrases)
    }
}
