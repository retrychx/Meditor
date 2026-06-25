# MEditor × GitLab Snippet 公网分享功能技术方案

> 版本：v1.0 · 日期：2026-06-14 · 作者：醉月

---

## 一、背景与目标

### 现状

MEditor 目前的"分享"功能基于内置 `NWListener` HTTP 服务，仅支持局域网访问：

- 访问者必须与分享者处于同一网络
- 链接无法跨网段（VPN / 异地 / 外部合作方）
- 适合"同桌看一眼"，无法满足异地协作场景

### 目标

新增 **GitLab Snippet 分享**功能，实现：

1. 一键将当前文档上传为 GitLab Snippet
2. 自动生成可分享的内网链接
3. 链接永久有效，收到方无需安装任何软件
4. 数据完全留在组织 GitLab，零安全风险

---

## 二、方案选型对比

| 方案 | 数据安全 | 实现成本 | 链接有效期 | 依赖 |
|------|----------|----------|------------|------|
| 局域网分享（现有） | ✅ 极高 | — | 临时 | 无 |
| ngrok 穿透 | ⚠️ 低（经第三方） | 低 | 临时 | ngrok 账号 |
| GitHub Gist | ✅ 高 | 低 | 永久 | GitHub 账号 |
| **GitLab Snippet（推荐）** | **✅ 极高（内网）** | **低** | **永久** | **组织 GitLab Token** |
| 自建云服务 | ✅ 极高 | 高 | 永久 | 服务器 |

**选择 GitLab Snippet 的原因：**
- 数据在组织内部 GitLab，符合安全规范
- 同事均有账号，可直接访问内部 Snippet
- GitLab REST API 简单，实现成本低
- 无需额外基础设施

---

## 三、功能设计

### 3.1 用户操作流程

```
菜单栏 File → Share → Publish to GitLab Snippet
             ↓
    首次使用：弹出配置面板
    ┌─────────────────────────────┐
    │  GitLab Host: [____________]│  ← 例: gitlab.xxx.com
    │  Personal Token: [_________]│  ← 用户 GitLab Token
    │  Visibility:  ○ Internal    │
    │               ○ Private     │
    │  [取消]           [保存并分享]│
    └─────────────────────────────┘
             ↓
    已配置：直接上传，显示进度
             ↓
    上传成功：弹出成功提示
    ┌─────────────────────────────┐
    │  ✅ 分享成功！              │
    │  https://gitlab.xxx.com/... │
    │  [复制链接]    [在浏览器打开]│
    └─────────────────────────────┘
```

### 3.2 分享选项

| 选项 | 说明 |
|------|------|
| **标题** | 默认使用文件名（不含扩展名），可修改 |
| **可见性** | Internal（组织内部可访问）/ Private（仅自己） |
| **更新模式** | 同文件再次分享时：新建 or 更新已有 Snippet |

### 3.3 Token 管理

- Token 存储在 macOS Keychain（`com.meditor.gitlab-token`）
- 不写入任何文件，不在日志中输出
- 设置页面（⌘,）新增 "GitLab 配置" 分组，支持查看/修改/清除

---

## 四、技术实现

### 4.1 新增文件结构

```
Sources/MEditor/
├── Services/
│   ├── GitLabService.swift          # API 封装 & Keychain 管理
│   └── ShareCoordinator.swift       # 分享流程协调（局域网 & GitLab 统一入口）
├── Views/
│   └── Share/
│       ├── GitLabConfigSheet.swift  # 首次配置弹窗
│       └── ShareSuccessSheet.swift  # 成功提示弹窗
└── Models/
    └── GitLabSnippet.swift          # API 请求/响应模型
```

### 4.2 GitLab API

#### 创建 Snippet

```
POST https://{host}/api/v4/snippets
Headers:
  PRIVATE-TOKEN: {token}
  Content-Type: application/json

Body:
{
  "title": "文件名.md",
  "description": "Shared via MEditor",
  "visibility": "internal",
  "files": [
    {
      "file_path": "文件名.md",
      "content": "文档内容..."
    }
  ]
}

Response:
{
  "id": 12345,
  "web_url": "https://gitlab.xxx.com/-/snippets/12345"
}
```

#### 更新 Snippet（再次分享同文件）

```
PUT https://{host}/api/v4/snippets/{id}
Headers:
  PRIVATE-TOKEN: {token}
  Content-Type: application/json

Body:
{
  "files": [
    {
      "action": "update",
      "file_path": "文件名.md",
      "content": "新内容..."
    }
  ]
}
```

### 4.3 GitLabService 核心实现（Swift）

```swift
actor GitLabService {
    
    // MARK: - Keychain
    
    private let keychainService = "com.meditor.gitlab"
    
    func saveToken(_ token: String, host: String) throws {
        // 存入 macOS Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: host,
            kSecValueData as String: token.data(using: .utf8)!
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func loadToken(for host: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: host,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - API
    
    func createSnippet(
        host: String,
        token: String,
        title: String,
        content: String,
        visibility: String = "internal"
    ) async throws -> String {
        let url = URL(string: "https://\(host)/api/v4/snippets")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "title": title,
            "description": "Shared via MEditor",
            "visibility": visibility,
            "files": [["file_path": title, "content": content]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw GitLabError.apiError
        }
        
        let json = try JSONDecoder().decode(GitLabSnippetResponse.self, from: data)
        return json.webUrl
    }
}
```

### 4.4 Snippet ID 持久化（支持更新）

用 `UserDefaults` 记录已上传过的文件路径 → Snippet ID 映射：

```swift
// key: 文件路径 MD5，value: snippet id
UserDefaults.standard.set(snippetId, forKey: "snippet.\(filePath.md5)")
```

再次分享同一文件时，弹出选择：**更新已有 Snippet** 或 **新建**。

---

## 五、设置页集成

在 `SettingsView` 新增 **"分享"** 分组：

```
┌─ 分享 ──────────────────────────────────┐
│                                          │
│  GitLab 主机地址                         │
│  [gitlab.xxx.com              ]          │
│                                          │
│  Personal Access Token                   │
│  [已配置 ●●●●●●●●    ] [清除]           │
│  （需要 api scope）                      │
│                                          │
│  默认可见性   ○ Internal  ○ Private      │
│                                          │
└──────────────────────────────────────────┘
```

Token 申请入口：在配置面板提供跳转链接
`https://{host}/-/user_settings/personal_access_tokens`

---

## 六、菜单栏集成

在 `File` 菜单 "Share" 子菜单下新增：

```
File
 └─ Share
     ├─ LAN Share...          （现有）
     ├─ ─────────────
     └─ Publish to GitLab...  （新增）
```

快捷键可选：`⌘⇧U`（Upload）

---

## 七、错误处理

| 错误场景 | 处理方式 |
|----------|----------|
| Token 未配置 | 弹出配置面板 |
| Token 无效（401） | 提示"Token 无效，请重新配置" |
| 网络不可达 | 提示"无法连接到 GitLab，请检查网络" |
| 权限不足（403） | 提示"Token 权限不足，需要 api scope" |
| Snippet 内容过大 | 提示"文件过大（>1MB），请拆分后分享" |

---

## 八、安全规范

1. **Token 只存 Keychain**，不落文件、不打日志
2. **HTTPS 强制**，不支持 HTTP GitLab 实例
3. **可见性默认 Internal**，不默认 Public
4. **分享前二次确认**（可在设置中关闭）
5. 本地记录的 Snippet ID 映射可在设置中一键清除

---

## 九、实施计划

| 阶段 | 内容 | 预计工时 |
|------|------|----------|
| P0 | GitLabService + Keychain + 创建 Snippet | 4h |
| P0 | 配置 Sheet + 成功 Sheet UI | 3h |
| P0 | 菜单集成 + 基础流程跑通 | 2h |
| P1 | 更新已有 Snippet（ID 持久化） | 2h |
| P1 | 设置页集成 | 2h |
| P2 | 错误处理完善 + 边界测试 | 2h |
| **合计** | | **~15h** |

---

## 十、验收标准

- [ ] 首次使用弹出配置面板，Token 保存到 Keychain
- [ ] 成功上传后链接自动复制到剪贴板
- [ ] 同事通过链接可访问（Internal 可见性）
- [ ] 再次分享同文件可选择更新已有 Snippet
- [ ] Token 在设置中可查看/修改/清除
- [ ] 所有网络错误有友好提示
- [ ] Token 不出现在任何日志输出中

---

*文档路径：`docs/gitlab-snippet-share.zh.md`*
