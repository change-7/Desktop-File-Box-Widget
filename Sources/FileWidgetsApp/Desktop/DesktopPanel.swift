import AppKit

final class DesktopPanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?
    var edgeResizeFrameChanged: ((CGRect) -> Void)?
    var edgeResizeActiveChanged: ((Bool) -> Void)?
    var isEdgeResizeEnabled = false {
        didSet {
            if !isEdgeResizeEnabled {
                finishEdgeResizeIfNeeded()
            }
        }
    }

    private let edgeResizeInset: CGFloat = 10
    private let cornerResizeInset: CGFloat = 34
    private var edgeResizeState: EdgeResizeState?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if handleEdgeResizeEvent(event) {
            return
        }

        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) == true {
            return
        }

        super.keyDown(with: event)
    }

    private func handleEdgeResizeEvent(_ event: NSEvent) -> Bool {
        guard isEdgeResizeEnabled else {
            return false
        }

        switch event.type {
        case .mouseMoved:
            if let edge = resizeEdge(at: event.locationInWindow) {
                cursor(for: edge).set()
            }
            return false

        case .leftMouseDown:
            guard let edge = resizeEdge(at: event.locationInWindow) else {
                return false
            }

            edgeResizeState = EdgeResizeState(
                edge: edge,
                startFrame: frame,
                startMouseLocation: NSEvent.mouseLocation
            )
            cursor(for: edge).set()
            edgeResizeActiveChanged?(true)
            return true

        case .leftMouseDragged:
            guard let edgeResizeState else {
                return false
            }

            edgeResizeFrameChanged?(resizedFrame(from: edgeResizeState, currentMouseLocation: NSEvent.mouseLocation))
            cursor(for: edgeResizeState.edge).set()
            return true

        case .leftMouseUp:
            guard edgeResizeState != nil else {
                return false
            }

            finishEdgeResizeIfNeeded()
            return true

        default:
            return false
        }
    }

    private func finishEdgeResizeIfNeeded() {
        guard edgeResizeState != nil else { return }
        edgeResizeState = nil
        edgeResizeActiveChanged?(false)
    }

    private func resizeEdge(at locationInWindow: NSPoint) -> WindowResizeEdge? {
        let windowSize = frame.size
        guard locationInWindow.x >= 0,
              locationInWindow.x <= windowSize.width,
              locationInWindow.y >= 0,
              locationInWindow.y <= windowSize.height else {
            return nil
        }

        let isNearLeft = locationInWindow.x <= cornerResizeInset
        let isNearRight = locationInWindow.x >= windowSize.width - cornerResizeInset
        let isNearBottom = locationInWindow.y <= cornerResizeInset
        let isNearTop = locationInWindow.y >= windowSize.height - cornerResizeInset

        if isNearRight && isNearBottom {
            return [.right, .bottom]
        }

        if isNearLeft && isNearBottom {
            return [.left, .bottom]
        }

        if isNearRight && isNearTop {
            return [.right, .top]
        }

        if isNearLeft && isNearTop {
            return [.left, .top]
        }

        var edge = WindowResizeEdge()
        if locationInWindow.x <= edgeResizeInset {
            edge.insert(.left)
        } else if locationInWindow.x >= windowSize.width - edgeResizeInset {
            edge.insert(.right)
        }

        if locationInWindow.y <= edgeResizeInset {
            edge.insert(.bottom)
        } else if locationInWindow.y >= windowSize.height - edgeResizeInset {
            edge.insert(.top)
        }

        return edge.isEmpty ? nil : edge
    }

    private func resizedFrame(from state: EdgeResizeState, currentMouseLocation: NSPoint) -> CGRect {
        let metrics = WidgetGridMetrics()
        let delta = CGSize(
            width: currentMouseLocation.x - state.startMouseLocation.x,
            height: currentMouseLocation.y - state.startMouseLocation.y
        )
        var resizedFrame = state.startFrame

        if state.edge.contains(.left) {
            let proposedMinX = state.startFrame.minX + delta.width
            let minX = state.startFrame.maxX - metrics.maximumPanelSize.width
            let maxX = state.startFrame.maxX - metrics.minimumPanelSize.width
            resizedFrame.origin.x = min(max(proposedMinX, minX), maxX)
            resizedFrame.size.width = state.startFrame.maxX - resizedFrame.minX
        } else if state.edge.contains(.right) {
            resizedFrame.size.width = min(
                max(state.startFrame.width + delta.width, metrics.minimumPanelSize.width),
                metrics.maximumPanelSize.width
            )
        }

        if state.edge.contains(.bottom) {
            let proposedMinY = state.startFrame.minY + delta.height
            let minY = state.startFrame.maxY - metrics.maximumPanelSize.height
            let maxY = state.startFrame.maxY - metrics.minimumPanelSize.height
            resizedFrame.origin.y = min(max(proposedMinY, minY), maxY)
            resizedFrame.size.height = state.startFrame.maxY - resizedFrame.minY
        } else if state.edge.contains(.top) {
            resizedFrame.size.height = min(
                max(state.startFrame.height + delta.height, metrics.minimumPanelSize.height),
                metrics.maximumPanelSize.height
            )
        }

        return resizedFrame
    }

    private func cursor(for edge: WindowResizeEdge) -> NSCursor {
        if edge.contains(.left) || edge.contains(.right) {
            return .resizeLeftRight
        }

        return .resizeUpDown
    }
}

private struct WindowResizeEdge: OptionSet {
    let rawValue: Int

    static let left = WindowResizeEdge(rawValue: 1 << 0)
    static let right = WindowResizeEdge(rawValue: 1 << 1)
    static let top = WindowResizeEdge(rawValue: 1 << 2)
    static let bottom = WindowResizeEdge(rawValue: 1 << 3)
}

private struct EdgeResizeState {
    let edge: WindowResizeEdge
    let startFrame: CGRect
    let startMouseLocation: NSPoint
}
