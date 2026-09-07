import AppKit
import SwiftUI

final class QuickPanelController: FloatingPanel {
    init(viewModel: QuickPanelViewModel) {
        super.init(contentView: NSHostingView(rootView: QuickPanelView(viewModel: viewModel)))
        onMoveDown = { viewModel.moveSelection(by: 1) }
        onMoveUp = { viewModel.moveSelection(by: -1) }
    }
}
