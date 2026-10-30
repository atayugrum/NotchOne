import SwiftUI

/// Hosting view that takes the first click, so buttons in the notch work even though
/// the panel never becomes key and the app stays in the background.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Files dragged over the window, or [] when the drag leaves or ends. Tracked at the
    /// window level so moving between SwiftUI drop zones doesn't count as leaving.
    var onDragChange: (([URL]) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDragChange?(DragPasteboard.fileURLs(sender.draggingPasteboard))
        return super.draggingEntered(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        onDragChange?([])
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        super.draggingEnded(sender)
        onDragChange?([])
    }
}

enum DragPasteboard {
    static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
