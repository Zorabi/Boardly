import SwiftUI

/// 右侧面板中的看板显示设置。它既可以在未选择任务时直接打开，
/// 也可以从任务详情标题栏的齿轮按钮进入。
struct BoardlySettingsView: View {
    @EnvironmentObject private var settings: BoardlySettings
    let onClose: () -> Void
    let onBack: (() -> Void)?

    init(onClose: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self.onClose = onClose
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(BoardlyTheme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BoardlyFormSection("文字大小") {
                        BoardlyFormRow(label: "预设") {
                            Picker(
                                "字体大小",
                                selection: Binding(
                                    get: { settings.fontSizePreset },
                                    set: { settings.fontSizePreset = $0 }
                                )
                            ) {
                                ForEach(BoardlySettings.FontSizePreset.allCases) { preset in
                                    Text(preset.title).tag(preset)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("自定义比例")
                                    .boardlyFont(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(settings.fontScale * 100))%")
                                    .boardlyFont(.caption, monospacedDigits: true)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.fontScale, in: 0.85...1.35, step: 0.01)
                                .tint(BoardlyTheme.accent)
                                .accessibilityLabel("字体大小比例")
                                .accessibilityValue("\(Int(settings.fontScale * 100))%")
                        }

                        Text("会同步调整看板、任务详情和表单文字。")
                            .boardlyFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    BoardlyFormSection("看板显示") {
                        BoardlyFormRow(label: "卡片密度") {
                            Picker("卡片密度", selection: $settings.cardDensity) {
                                ForEach(BoardlySettings.CardDensity.allCases) { density in
                                    Text(density.title).tag(density)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        Toggle("显示任务说明", isOn: $settings.showTaskNotes)
                            .toggleStyle(.switch)
                        Toggle("显示任务元数据", isOn: $settings.showTaskMetadata)
                            .toggleStyle(.switch)
                    }

                    Button("恢复默认设置") {
                        settings.resetToDefaults()
                    }
                    .buttonStyle(BoardlySecondaryButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHint("将字体、卡片密度和显示选项恢复为默认值")
                }
                .padding(16)
            }
            .boardlyScrollers()
        }
        .background(BoardlyTheme.canvas)
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BoardlyIconButtonStyle())
                .accessibilityLabel("返回任务详情")
            }

            Label("看板设置", systemImage: "textformat.size")
                .boardlyFont(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(BoardlyIconButtonStyle())
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("关闭看板设置")
        }
        .padding(16)
    }
}
