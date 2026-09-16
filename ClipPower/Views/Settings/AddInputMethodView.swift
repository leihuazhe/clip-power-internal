import SwiftUI

/// "添加输入法" 弹层：只能从系统里已启用、且还没被绑定过的输入源中选一个。
struct AddInputMethodView: View {
    let availableInputSources: [InputSourceInfo]
    let onSelect: (InputSourceInfo) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if availableInputSources.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("没有更多可添加的输入法了，请先在系统设置里启用更多输入法。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                List(availableInputSources) { inputSource in
                    Button {
                        onSelect(inputSource)
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundStyle(.secondary)
                            Text(inputSource.localizedName)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("取消", role: .cancel) { onCancel() }
            }
            .padding()
        }
        .navigationTitle("选择输入法")
        .frame(minWidth: 320, minHeight: 320)
    }
}
