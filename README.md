# Boardly

Boardly 是一个从 Todos.dev 的克制深色界面获得启发、但专注于人类个人待办的 macOS 原生看板原型。

当前仓库包含：

- SwiftUI 可运行视觉原型。
- [产品与交互设计](docs/PRODUCT_DESIGN.md)。
- [设计系统](design-system/todos-mac/MASTER.md)。

核心范围是项目、四列看板、任务详情 Inspector、搜索、快捷键、原生拖放和本地 JSON 持久化；不包含定时执行、团队协作或 AI Agent 资源管理。原型默认使用深色外观，不跟随系统浅色模式。

## 运行

```bash
swift run
```

要求 macOS 14 或更高版本及对应的 Xcode Command Line Tools。
