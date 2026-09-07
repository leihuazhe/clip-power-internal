import AppKit
import SwiftUI

final class ClipboardHistoryPanelController: FloatingPanel {
    init(viewModel: ClipboardHistoryViewModel) {
        super.init(contentView: NSHostingView(rootView: ClipboardHistoryView(viewModel: viewModel)))
        onMoveDown = { viewModel.moveSelection(by: 1) }
        onMoveUp = { viewModel.moveSelection(by: -1) }
    }
}
