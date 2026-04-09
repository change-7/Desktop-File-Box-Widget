import AppKit

final class DesktopPanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}
