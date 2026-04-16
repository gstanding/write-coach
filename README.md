# WritingCoach

一个本地优先的写作教练内核（Swift Package）+ CLI 工具，面向“更自然、更像稳定人类作者”的长文写作流程。

## 目录结构

- `Sources/WritingCoachCore`：核心能力（ULID、FrontMatter、规则引擎、公众号 HTML 导入、索引存储）
- `Sources/WritingCoachCLI`：命令行工具 `writingcoach`
- `Apps/`：macOS / iOS 的 SwiftUI App 子工程（在 macOS 的 Xcode 中打开并运行）

## 本地验证（Linux / CI）

```bash
swift test
swift run writingcoach --root /tmp/my-library init
swift run writingcoach --root /tmp/my-library new --title "测试"
swift run writingcoach --root /tmp/my-library list
```

## Library（Vault）落盘格式

- `docs/{ulid}.md`：正文（Markdown），顶部 YAML Front Matter
- `assets/{ulid}/{sha256}.{ext}`：导入图片与附件
- `index.sqlite`：索引与元数据
- `settings.json`：本地偏好

## App（macOS / iOS）

`Apps/WritingCoachMacApp`、`Apps/WritingCoachiOSApp` 是两个独立的 SwiftPM 工程，依赖根目录的 `WritingCoachCore`。

在 macOS 上用 Xcode 打开对应的 `Apps/*/Package.swift` 即可编译运行。

