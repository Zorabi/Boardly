import SwiftUI
import AppKit

@main
struct BoardlyApp: App {
    @StateObject private var store = BoardStore.live
    @StateObject private var settings = BoardlySettings()

    var body: some Scene {
        WindowGroup {
            BoardWorkspaceView()
                .environmentObject(store)
                .environmentObject(settings)
                .environment(\.boardlyFontScale, settings.fontScale)
                .environment(\.dynamicTypeSize, settings.dynamicTypeSize)
                .frame(minWidth: 960, minHeight: 620)
                .tint(BoardlyTheme.accent)
                .preferredColorScheme(.dark)
                // 标题栏/工具栏与深色语义色板统一（由 BoardlyWindowChrome 以
                // Theme.toolbar 令牌配置窗口 chrome）；保留原生交通灯、
                // 窗口拖动、工具栏按钮与搜索框。
                .background(BoardlyWindowChrome())
                .background(BoardlyTheme.canvas)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // 终止通知仍在主线程发送；这里刻意同步排空最新快照，避免最后一次编辑丢失。
                    store.flushPersistence()
                }
        }
        .defaultSize(width: 1_280, height: 780)
    }
}
