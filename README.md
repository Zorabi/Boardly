<div align="center">

# Boardly

一款原生、离线优先的 macOS 个人任务看板。

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)](https://github.com/Zorabi/Boardly)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](Package.swift)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0D96F6)](Sources/Boardly)
[![MIT License](https://img.shields.io/badge/License-MIT-2F855A)](LICENSE)

</div>

Boardly 使用 SwiftUI 构建，为个人任务提供项目分类、自定义工作流、拖放排序、任务详情和本地持久化。应用无需账号或网络服务，数据保存在当前 Mac 上。

> [!NOTE]
> Boardly 目前处于可运行的原型阶段，尚未提供签名安装包或自动更新。请通过 SwiftPM 运行，或使用仓库脚本生成本地 `.app`。

## 界面预览

![Boardly 主看板，包含项目侧边栏、搜索和五列任务工作流](docs/images/boardly-board.png)

<p align="center">
  <img src="docs/images/boardly-inspector.png" alt="任务详情 Inspector" width="49%">
  <img src="docs/images/boardly-settings.png" alt="看板显示设置" width="49%">
</p>

<p align="center"><sub>截图使用应用内置示例数据，不包含真实个人任务。</sub></p>

## 功能

- **自定义工作流**：新增、编辑、排序和删除看板列，并为列设置图标、颜色和完成语义。
- **任务管理**：记录标题、描述、优先级、项目、截止日期和标签；支持列内排序与跨列拖放。
- **聚焦视图**：按项目、未分类、今天或所有任务查看看板，并可从工具栏搜索任务。
- **原生 macOS 体验**：SwiftUI 三栏布局、右侧 Inspector、系统字体、SF Symbols 和键盘操作。
- **显示偏好**：调整字号、卡片密度，以及任务描述和元数据的显示方式。
- **本地持久化**：任务自动写入本地 JSON；旧版数据迁移或损坏数据恢复前会保留原始备份。
- **辅助功能**：支持 VoiceOver 文案、键盘入口和“减弱动态效果”设置。

## 快速开始

### 环境要求

- macOS 14 Sonoma 或更高版本
- Swift 6 toolchain
- Xcode Command Line Tools

项目不依赖第三方 Swift Package。

### 从源码运行

```bash
git clone https://github.com/Zorabi/Boardly.git
cd Boardly
swift run
```

也可以先构建，再运行调试版二进制：

```bash
swift build
.build/debug/Boardly
```

### 生成 macOS 应用

```bash
bash Sources/Boardly/Resources/make-app.sh
open build/Boardly.app
```

脚本会执行 Release 构建、生成应用图标，并输出 `build/Boardly.app`。生成结果使用 ad-hoc 签名，仅适合本地开发和体验，不是经过 Developer ID 签名与公证的发行包。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 新建任务 | <kbd>⌘</kbd> <kbd>N</kbd> |
| 打开或关闭看板设置 | <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>I</kbd> |
| 关闭任务详情或弹窗 | <kbd>Esc</kbd> |
| 确认表单 | <kbd>Return</kbd> |

## 数据与隐私

Boardly 不包含账号、在线同步、遥测或后台服务。

| 数据 | 保存位置 |
| --- | --- |
| 项目、列和任务 | `~/Library/Application Support/Boardly/board.json` |
| 字号、卡片密度等显示偏好 | macOS `UserDefaults` |
| 迁移与恢复备份 | `~/Library/Application Support/Boardly/*.backup` |

首次启动且不存在 `board.json` 时，Boardly 会载入一组示例项目和任务。当前数据格式为 schema v2，并兼容旧版 `status` 字段。

## 开发与测试

运行全部测试：

```bash
swift test
```

测试覆盖数据解码与迁移、自定义列、任务移动与排序、备份恢复，以及显示设置持久化。

主要目录：

```text
Sources/Boardly/           应用源码与打包资源
Tests/BoardlyTests/        单元测试
docs/images/               README 截图
docs/PRODUCT_DESIGN.md     产品与交互设计
design-system/todos-mac/   macOS 视觉规范
```

进一步了解设计与实现约束：

- [产品与交互设计](docs/PRODUCT_DESIGN.md)
- [macOS 视觉规范](design-system/todos-mac/MASTER.md)

## 贡献

欢迎提交 [Issue](https://github.com/Zorabi/Boardly/issues) 或 Pull Request。提交代码前请运行 `swift test`；涉及界面调整时，建议附上变更前后的截图。

## License

Boardly 基于 [MIT License](LICENSE) 发布。
