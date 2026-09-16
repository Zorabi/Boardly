# Boardly

Boardly 是一个从 Todos.dev 的克制深色界面获得启发、但专注于人类个人待办的 macOS 原生看板原型。

当前仓库包含：

- SwiftUI 可运行视觉原型。
- [产品与交互设计](docs/PRODUCT_DESIGN.md)。
- [设计系统](design-system/todos-mac/MASTER.md)。

核心范围是项目、可自定义列看板（默认四列：待办/进行中/已完成，可增删改名、调整顺序）、任务详情 Inspector、搜索、快捷键、原生拖放和本地 JSON 持久化；不包含定时执行、团队协作或 AI Agent 资源管理。原型默认使用深色外观，不跟随系统浅色模式。旧版本按 `status` 存储的任务会在读取时自动迁移到对应的默认列。

## 运行

```bash
swift run
```

要求 macOS 14 或更高版本及对应的 Xcode Command Line Tools。

## 打包为带图标的应用

`swift run` 不会生成 .app 包，Finder 中也就没有自定义图标。仓库内置了应用图标源文件与打包脚本：

```bash
bash Sources/Boardly/Resources/make-app.sh
```

脚本会执行 release 构建，把 `Sources/Boardly/Resources/AppIcon.iconset`（CoreGraphics 生成的深色看板图标）用 `iconutil` 编译为 icns，写入带 `CFBundleIconFile` 的 Info.plist，并做临时签名，最终产出 `build/Boardly.app`。双击即可启动，Dock 与 Finder 会显示自定义图标。
