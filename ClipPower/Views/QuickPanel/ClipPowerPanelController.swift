import AppKit
import SwiftUI

final class ClipPowerPanelController: FloatingPanel {
    init(viewModel: ClipPowerPanelViewModel) {
        super.init(contentView: NSHostingView(rootView: ClipPowerPanelView(viewModel: viewModel)))
        onMoveDown = { viewModel.moveSelection(by: 1) }
        onMoveUp = { viewModel.moveSelection(by: -1) }
        onTabKey = { viewModel.cycleTab() }
    }
}
