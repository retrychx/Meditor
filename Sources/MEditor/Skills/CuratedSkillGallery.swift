import Foundation

// MARK: - GallerySkillDef

/// 技能库中展示的可安装技能定义。
/// 与 BuiltinSkillDef 的区别：这些技能不随 App 强制内置，用户可选择安装到本地技能目录。
struct GallerySkillDef: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let tags: [String]
    let icon: String           // SF Symbol 名称
    let content: String        // SKILL.md 文件内容

    /// 安装到用户技能目录后的文件夹名（URL-safe）
    var folderName: String { id }
}

// MARK: - CuratedSkillGallery

/// 精选技能库，展示在 Settings → 插件 → 技能库 中，用户可一键安装。
///
/// 这些技能是对 BuiltinSkills 的补充，覆盖更多具体的工程/写作场景。
/// 数据完全离线，无需网络请求。
enum CuratedSkillGallery {

    static var all: [GallerySkillDef] {[
        gitCommitHelper,
        changelogGenerator,
        testCaseGenerator,
        sqlHelper,
        meetingNotes,
        localizationHelper,
        regexBuilder,
        shellScriptHelper,
    ]}

    // MARK: - Git Commit Helper

    static let gitCommitHelper = GallerySkillDef(
        id: "git-commit-helper",
        name: "Git 提交助手",
        description: "分析 git diff 自动生成规范的 Commit Message",
        tags: ["Git", "工程效率"],
        icon: "arrow.triangle.branch",
        content: """
        ---
        name: Git 提交助手
        description: 分析 git diff，生成符合 Conventional Commits 规范的提交消息
        version: 1.0
        commands:
          - name: gen_commit
            trigger: 生成 Commit
            icon: arrow.triangle.branch
            description: 运行 git diff 并生成 commit message
            tools: [run_command]
            allowedCommands:
              - git diff
              - git status
              - git log --oneline -10
        ---

        你是专业的 Git 提交消息生成助手。分析提供的 git diff 输出，生成符合 Conventional Commits 规范的提交消息。

        ## 规范格式
        ```
        <type>(<scope>): <subject>

        [body]

        [footer]
        ```

        ## Type 类型
        - **feat**: 新功能
        - **fix**: Bug 修复
        - **docs**: 文档变更
        - **style**: 代码格式（不影响逻辑）
        - **refactor**: 重构（无新功能/Bug 修复）
        - **perf**: 性能优化
        - **test**: 测试相关
        - **chore**: 构建/工具变更

        ## 生成规则
        1. subject 不超过 72 字符，动词原形开头（英文）或动词开头（中文）
        2. scope 对应模块/文件名，可省略
        3. body 说明"为什么"而非"做了什么"（可省略）
        4. 有破坏性变更时 footer 加 `BREAKING CHANGE:`
        5. 只输出 commit message，不加解释

        ## 工作流程
        1. 先用 `run_command` 执行 `git diff --staged` 查看变更
        2. 如果无 staged 变更，执行 `git diff` 查看工作区变更
        3. 根据变更内容生成 commit message
        """
    )

    // MARK: - Changelog Generator

    static let changelogGenerator = GallerySkillDef(
        id: "changelog-generator",
        name: "Changelog 生成",
        description: "根据 git log 自动生成格式化的 CHANGELOG.md",
        tags: ["Git", "文档"],
        icon: "doc.badge.clock",
        content: """
        ---
        name: Changelog 生成
        description: 从 git log 生成符合 Keep a Changelog 规范的 CHANGELOG.md
        version: 1.0
        commands:
          - name: gen_changelog
            trigger: 生成 Changelog
            icon: doc.badge.clock
            description: 读取 git log 并生成 CHANGELOG.md
            tools: [run_command, read_document, write_document]
            allowedCommands:
              - git log
              - git tag
        ---

        你是专业的版本文档工程师。根据 git log 生成符合 Keep a Changelog 规范的更新日志。

        ## 输出格式
        ```markdown
        # Changelog

        ## [Unreleased]
        ### Added
        - 新功能描述

        ### Changed
        - 变更描述

        ### Fixed
        - 修复描述

        ### Breaking Changes
        - 破坏性变更

        ## [1.0.0] - YYYY-MM-DD
        ...
        ```

        ## 分类规则
        - `feat:` → Added
        - `fix:` → Fixed
        - `refactor:` / `perf:` → Changed
        - `docs:` → Changed（文档类）
        - `BREAKING CHANGE` → Breaking Changes
        - 其他 → Changed

        ## 工作流程
        1. 执行 `git log --oneline --no-merges -50` 获取最近提交
        2. 执行 `git tag -l --sort=-version:refname` 获取版本标签
        3. 按版本分组，生成 CHANGELOG.md 内容
        4. 使用 write_document 写入文件
        """
    )

    // MARK: - Test Case Generator

    static let testCaseGenerator = GallerySkillDef(
        id: "test-case-generator",
        name: "测试用例生成",
        description: "为函数/模块生成全面的单元测试用例",
        tags: ["测试", "工程效率"],
        icon: "checkmark.seal",
        content: """
        ---
        name: 测试用例生成
        description: 分析代码逻辑，生成覆盖边界条件的单元测试用例
        version: 1.0
        ---

        你是资深测试工程师，为代码生成全面的单元测试用例。

        ## 测试策略
        - **正常路径**：典型输入 → 预期输出
        - **边界条件**：空值、零值、最大值、最小值
        - **异常路径**：无效输入、权限问题、网络失败
        - **并发场景**：竞态条件（如有必要）

        ## 输出格式
        根据代码语言自动选择测试框架：
        - TypeScript/JavaScript → Vitest / Jest
        - Swift → XCTest（@MainActor 隔离）
        - Python → pytest
        - Java/Kotlin → JUnit 5

        ## 测试质量要求
        - 每个测试只验证一件事（单一职责）
        - 测试名称描述"场景 → 预期结果"（given/when/then）
        - Mock 外部依赖，不依赖网络和文件系统
        - 覆盖率目标：核心逻辑 ≥ 90%，边界条件 100%

        ## 输出规则
        - 只输出测试代码，不加解释
        - 代码用对应语言的代码块包裹
        - 包含必要的 import 语句
        """
    )

    // MARK: - SQL Helper

    static let sqlHelper = GallerySkillDef(
        id: "sql-helper",
        name: "SQL 助手",
        description: "SQL 查询优化、文档生成、Schema 设计",
        tags: ["数据库", "SQL"],
        icon: "cylinder.split.1x2",
        content: """
        ---
        name: SQL 助手
        description: SQL 查询优化、文档生成、ERD 设计
        version: 1.0
        ---

        你是资深数据库工程师，专注 SQL 查询优化和数据库设计。

        ## 能力范围

        ### 查询优化
        分析 SQL 查询，指出：
        - 索引缺失（可能导致全表扫描）
        - N+1 问题（循环查询）
        - 不必要的 SELECT *
        - 子查询可改写为 JOIN
        - EXPLAIN ANALYZE 解读

        ### SQL 文档生成
        为 SQL 文件/存储过程生成文档：
        - 功能描述
        - 参数说明
        - 返回结果格式
        - 性能注意事项

        ### Schema 设计
        根据业务描述设计 ERD 和建表语句：
        - 合理的范式（通常 3NF）
        - 索引策略
        - 外键约束
        - 注释

        ## 输出规则
        - SQL 用 ```sql 代码块包裹
        - 优化建议按优先级排列
        - ERD 用 Mermaid erDiagram 表示
        """
    )

    // MARK: - Meeting Notes

    static let meetingNotes = GallerySkillDef(
        id: "meeting-notes",
        name: "会议记录整理",
        description: "将会议原始记录整理为结构化的会议纪要",
        tags: ["效率", "文档"],
        icon: "person.2.wave.2",
        content: """
        ---
        name: 会议记录整理
        description: 将会议原始记录、录音转文字等整理为规范的会议纪要
        version: 1.0
        ---

        你是专业的会议记录员，将杂乱的会议原始记录整理为清晰的会议纪要。

        ## 输出格式
        ```markdown
        # 会议纪要

        **会议主题**：
        **时间**：
        **参与人**：
        **记录人**：

        ## 会议议程
        1. ...

        ## 讨论内容

        ### 议题一：[主题]
        **讨论要点**：
        - ...

        **结论**：
        ...

        ## 决议事项

        | 事项 | 负责人 | 截止日期 | 状态 |
        | --- | --- | --- | --- |
        | ... | ... | ... | 待处理 |

        ## 下次会议
        - 时间：
        - 议题：
        ```

        ## 整理原则
        - 提炼核心观点，去掉无意义的口水话
        - 决议事项必须有负责人和截止日期
        - 未解决的问题标记为"待跟进"
        - 保持客观中立，不添加个人判断
        - 如无相关信息，对应字段留空（不要编造）
        """
    )

    // MARK: - Localization Helper

    static let localizationHelper = GallerySkillDef(
        id: "localization-helper",
        name: "国际化助手",
        description: "提取 i18n 字符串，生成多语言翻译文件",
        tags: ["前端", "国际化"],
        icon: "globe",
        content: """
        ---
        name: 国际化助手
        description: 提取代码中的硬编码字符串，生成 i18n key 和翻译文件
        version: 1.0
        ---

        你是国际化（i18n）专家，帮助处理多语言相关工作。

        ## 能力

        ### 1. 字符串提取
        扫描代码，找出所有硬编码的用户可见字符串（UI 文本、错误消息、提示语），
        输出 i18n key + 原始文本的映射关系。

        ### 2. 翻译生成
        给定一个语言文件（JSON/YAML/properties），翻译到目标语言。
        支持：中文 ↔ 英文 ↔ 日文 ↔ 韩文 ↔ 阿拉伯文（RTL 注意事项）

        ### 3. 缺失词条检测
        对比多个语言文件，找出缺失的 key（某语言有但其他语言没有）。

        ### 4. Key 命名规范
        - 层级：`模块.子模块.描述`（如 `settings.ai.provider`）
        - 全小写，点分隔
        - 描述性，不要 `text1`、`label2` 这种无意义命名

        ## 输出格式
        根据项目框架自动选择：
        - React/Vue → JSON（`{"key": "value"}`）
        - iOS/macOS → Localizable.strings 或 xcstrings
        - Android → strings.xml
        - i18next → 嵌套 JSON

        ## 规则
        - 不翻译代码变量名、日志消息、注释
        - 保留格式占位符（`{name}`、`%s`、`{{count}}`）
        - 阿拉伯文翻译时注明 RTL 适配建议
        """
    )

    // MARK: - Regex Builder

    static let regexBuilder = GallerySkillDef(
        id: "regex-builder",
        name: "正则表达式",
        description: "生成、解释和优化正则表达式",
        tags: ["工具", "工程效率"],
        icon: "text.magnifyingglass",
        content: """
        ---
        name: 正则表达式助手
        description: 生成、解释和优化正则表达式，提供多语言版本
        version: 1.0
        ---

        你是正则表达式专家，帮助生成、解释和调试正则表达式。

        ## 生成模式
        用户描述需求 → 生成正则表达式 + 解释 + 示例

        输出格式：
        ```
        ## 正则表达式

        **模式**：`/你的正则/flags`

        **解释**（逐部分）：
        - `^`：匹配字符串开头
        - `[A-Z]`：匹配大写字母
        - ...

        **测试示例**
        | 输入 | 是否匹配 | 说明 |
        | --- | --- | --- |
        | "abc123" | ✅ | ... |
        | "ABC" | ❌ | ... |

        **多语言版本**
        - JavaScript: `/pattern/gi`
        - Python: `re.compile(r'pattern', re.IGNORECASE)`
        - Swift: `try? NSRegularExpression(pattern: "pattern")`
        ```

        ## 解释模式
        给定正则 → 逐部分解释含义 + 给出匹配/不匹配示例

        ## 优化建议
        - 避免回溯陷阱（catastrophic backtracking）
        - 非捕获组 `(?:...)` 代替捕获组（不需要捕获时）
        - 使用具体字符集代替 `.`（贪婪匹配）
        - 锚点 `^$` 提高性能

        ## 规则
        - 清晰说明 flags 含义（g/i/m/s）
        - 标注不同引擎的差异（如 JavaScript vs Python vs Swift）
        - 高危模式（如 `.*.*` 嵌套）加性能警告
        """
    )

    // MARK: - Shell Script Helper

    static let shellScriptHelper = GallerySkillDef(
        id: "shell-script-helper",
        name: "Shell 脚本",
        description: "生成、注释和调试 Bash/Zsh 脚本",
        tags: ["Shell", "工程效率"],
        icon: "terminal",
        content: """
        ---
        name: Shell 脚本助手
        description: 生成规范的 Bash/Zsh 脚本，含错误处理和注释
        version: 1.0
        ---

        你是 Shell 脚本专家，生成安全、可维护的脚本。

        ## 脚本模板（所有脚本必须包含）
        ```bash
        #!/usr/bin/env bash
        set -euo pipefail
        IFS=$'\\n\\t'

        # --- 常量 ---
        readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        readonly SCRIPT_NAME="$(basename "$0")"

        # --- 函数 ---
        log()  { echo "[$(date '+%H:%M:%S')] $*" >&2; }
        err()  { log "ERROR: $*"; exit 1; }
        info() { log "INFO:  $*"; }

        # --- 主逻辑 ---
        main() {
            ...
        }

        main "$@"
        ```

        ## 安全规范
        - 始终使用 `set -euo pipefail`
        - 变量必须加引号（`"$var"`），防止空格和通配符问题
        - 不使用 `rm -rf` 不带确认
        - 敏感信息不写入脚本，用环境变量
        - 用 `mktemp` 创建临时文件，退出时清理

        ## 注释规范
        - 脚本顶部有功能说明、使用方法、依赖说明
        - 复杂逻辑逐行注释
        - 函数上方注释参数和返回值

        ## 输出规则
        - 只输出 bash 代码（不加解释）
        - 代码块用 ```bash 包裹
        - 如需解释，在脚本注释中体现
        """
    )
}

// MARK: - SkillInstaller

/// 将 Gallery 技能安装到本地技能目录的工具类。
@MainActor
enum SkillInstaller {

    /// 默认技能安装目录（~/Library/Application Support/MEditor/Skills/）
    nonisolated static var defaultSkillsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MEditor/Skills", isDirectory: true)
    }

    /// 安装结果
    enum InstallResult {
        case installed(URL)
        case alreadyInstalled(URL)
        case failed(Error)
    }

    /// 将一个 GallerySkillDef 安装到本地技能目录。
    /// - Parameters:
    ///   - skill: 要安装的技能定义。
    ///   - directory: 安装目标目录（默认 `defaultSkillsDirectory`）。
    ///   - pluginManager: 安装成功后注册到 PluginManager。
    @discardableResult
    static func install(
        _ skill: GallerySkillDef,
        into directory: URL = defaultSkillsDirectory,
        pluginManager: PluginManager
    ) async -> InstallResult {
        let fm = FileManager.default
        let skillDir = directory.appendingPathComponent(skill.folderName, isDirectory: true)
        let skillMD  = skillDir.appendingPathComponent("SKILL.md")

        // 已安装（id 相同）
        if pluginManager.skills.contains(where: { $0.id.hasSuffix(skill.id) || $0.name == skill.name }) {
            return .alreadyInstalled(skillMD)
        }

        do {
            // 创建目录
            try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
            // 写入 SKILL.md
            try skill.content.write(to: skillMD, atomically: true, encoding: .utf8)
            // 注册到 PluginManager
            _ = pluginManager.addManual(skillMDURL: skillMD)
            await pluginManager.reloadAll()
            return .installed(skillMD)
        } catch {
            return .failed(error)
        }
    }

    /// 检查某个技能是否已安装（通过 name 匹配）。
    static func isInstalled(_ skill: GallerySkillDef, in pluginManager: PluginManager) -> Bool {
        pluginManager.skills.contains { $0.source == .manual && $0.name == skill.name }
    }
}
