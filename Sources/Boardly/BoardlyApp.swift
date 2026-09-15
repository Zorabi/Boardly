import SwiftUI

@main
struct BoardlyApp: App {
    @StateObject private var store = BoardStore.live

    var body: some Scene {
        WindowGroup {
            BoardWorkspaceView()
                .environmentObject(store)
                .frame(minWidth: 960, minHeight: 620)
                .tint(BoardlyTheme.accent)
                .preferredColorScheme(.dark)
                // 标题栏/工具栏与深色语义色板统一（由 BoardlyWindowChrome 以
                // Theme.toolbar 令牌配置窗口 chrome）；保留原生交通灯、
                // 窗口拖动、工具栏按钮与搜索框。
                .background(BoardlyWindowChrome())
                .background(BoardlyTheme.canvas)
        }
        .defaultSize(width: 1_280, height: 780)
    }
}
