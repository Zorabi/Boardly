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
                .background(BoardlyTheme.canvas)
        }
        .defaultSize(width: 1_280, height: 780)
    }
}
