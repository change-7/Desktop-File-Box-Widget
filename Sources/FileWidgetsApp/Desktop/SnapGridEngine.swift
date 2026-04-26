import AppKit

struct WidgetFrameSnapshot: Equatable {
    let widgetID: UUID
    let frame: CGRect
}

enum WidgetSnapMode {
    case move
    case resizeBottomTrailing
}

struct SnapGridEngine {
    private let metrics = WidgetGridMetrics()
    private let blockedOverlapTolerance: CGFloat = 10

    func resolveFrame(
        for proposedFrame: CGRect,
        on screen: NSScreen,
        occupied: [WidgetFrameSnapshot],
        blockedFrames: [CGRect],
        mode: WidgetSnapMode
    ) -> CGRect? {
        let screenFrame = screen.visibleFrame
        let clampedFrame = clamp(proposedFrame, to: screenFrame)
        let snappedFrame = snap(clampedFrame, occupied: occupied, mode: mode)

        if isValid(snappedFrame, occupied: occupied, blockedFrames: blockedFrames) {
            return normalize(snappedFrame)
        }

        if framesDiffer(snappedFrame, clampedFrame),
           isValid(clampedFrame, occupied: occupied, blockedFrames: blockedFrames) {
            return normalize(clampedFrame)
        }

        return nil
    }

    func screenIdentifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }

        let origin = screen.frame.origin
        let size = screen.frame.size
        return "\(Int(origin.x)):\(Int(origin.y)):\(Int(size.width)):\(Int(size.height))"
    }

    private func clamp(_ frame: CGRect, to screenFrame: CGRect) -> CGRect {
        let clampedSize = metrics.clampedPanelSize(frame.size)
        let minX = screenFrame.minX + metrics.desktopInset
        let maxX = screenFrame.maxX - metrics.desktopInset - clampedSize.width
        let minY = screenFrame.minY + metrics.desktopInset
        let maxY = screenFrame.maxY - metrics.desktopInset - clampedSize.height

        return CGRect(
            x: min(max(frame.minX, minX), maxX),
            y: min(max(frame.minY, minY), maxY),
            width: clampedSize.width,
            height: clampedSize.height
        )
    }

    private func snap(_ frame: CGRect, occupied: [WidgetFrameSnapshot], mode: WidgetSnapMode) -> CGRect {
        guard !occupied.isEmpty else { return frame }

        switch mode {
        case .move:
            let snappedOrigin = CGPoint(
                x: snappedMoveX(for: frame, occupied: occupied),
                y: snappedMoveY(for: frame, occupied: occupied)
            )
            return CGRect(origin: snappedOrigin, size: frame.size)

        case .resizeBottomTrailing:
            let snappedSize = snappedResizeSize(for: frame, occupied: occupied)
            return CGRect(
                x: frame.minX,
                y: frame.maxY - snappedSize.height,
                width: snappedSize.width,
                height: snappedSize.height
            )
        }
    }

    private func snappedMoveX(for frame: CGRect, occupied: [WidgetFrameSnapshot]) -> CGFloat {
        let candidates = occupied.flatMap { snapshot in
            [
                snapshot.frame.minX,
                snapshot.frame.maxX - frame.width,
                snapshot.frame.midX - (frame.width / 2),
            ]
        }
        return nearestSnapValue(to: frame.minX, candidates: candidates)
    }

    private func snappedMoveY(for frame: CGRect, occupied: [WidgetFrameSnapshot]) -> CGFloat {
        let candidates = occupied.flatMap { snapshot in
            [
                snapshot.frame.minY,
                snapshot.frame.maxY - frame.height,
                snapshot.frame.midY - (frame.height / 2),
            ]
        }
        return nearestSnapValue(to: frame.minY, candidates: candidates)
    }

    private func snappedResizeSize(for frame: CGRect, occupied: [WidgetFrameSnapshot]) -> CGSize {
        let proposedWidth = frame.width
        let proposedHeight = frame.height
        let proposedRight = frame.maxX
        let proposedBottom = frame.minY

        let widthAlignedWidgets = occupied.filter { snapshot in
            isNear(snapshot.frame.minX, frame.minX)
                || isNear(snapshot.frame.midX, frame.midX)
                || isNear(snapshot.frame.maxX, proposedRight)
        }

        let heightAlignedWidgets = occupied.filter { snapshot in
            isNear(snapshot.frame.maxY, frame.maxY)
                || isNear(snapshot.frame.midY, frame.midY)
                || isNear(snapshot.frame.minY, proposedBottom)
        }

        let widthCandidates = widthAlignedWidgets.flatMap { snapshot in
            [
                snapshot.frame.width,
                snapshot.frame.maxX - frame.minX,
            ]
        }.filter { $0 >= metrics.minimumPanelSize.width && $0 <= metrics.maximumPanelSize.width }

        let heightCandidates = heightAlignedWidgets.flatMap { snapshot in
            [
                snapshot.frame.height,
                frame.maxY - snapshot.frame.minY,
            ]
        }.filter { $0 >= metrics.minimumPanelSize.height && $0 <= metrics.maximumPanelSize.height }

        let rightEdgeCandidates = widthAlignedWidgets.map(\.frame.maxX)
        let bottomEdgeCandidates = heightAlignedWidgets.map(\.frame.minY)

        var snappedWidth = nearestSnapValue(to: proposedWidth, candidates: widthCandidates)
        let snappedRight = nearestSnapValue(to: proposedRight, candidates: rightEdgeCandidates)
        if abs(snappedRight - proposedRight) <= metrics.alignmentSnapThreshold {
            snappedWidth = snappedRight - frame.minX
        }

        var snappedHeight = nearestSnapValue(to: proposedHeight, candidates: heightCandidates)
        let snappedBottom = nearestSnapValue(to: proposedBottom, candidates: bottomEdgeCandidates)
        if abs(snappedBottom - proposedBottom) <= metrics.alignmentSnapThreshold {
            snappedHeight = frame.maxY - snappedBottom
        }

        return metrics.clampedPanelSize(
            CGSize(width: snappedWidth, height: snappedHeight)
        )
    }

    private func isNear(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) <= (metrics.alignmentSnapThreshold * 2)
    }

    private func nearestSnapValue(to proposed: CGFloat, candidates: [CGFloat]) -> CGFloat {
        guard let best = candidates.min(by: { abs($0 - proposed) < abs($1 - proposed) }) else {
            return proposed
        }

        return abs(best - proposed) <= metrics.alignmentSnapThreshold ? best : proposed
    }

    private func isValid(_ frame: CGRect, occupied: [WidgetFrameSnapshot], blockedFrames: [CGRect]) -> Bool {
        let effectiveFrame = frame.insetBy(dx: blockedOverlapTolerance, dy: blockedOverlapTolerance)
        guard !blockedFrames.contains(where: { $0.intersects(effectiveFrame) }) else {
            return false
        }

        return occupied.allSatisfy { !$0.frame.intersects(frame) }
    }

    private func normalize(_ frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX.rounded(),
            y: frame.minY.rounded(),
            width: frame.width.rounded(),
            height: frame.height.rounded()
        )
    }

    private func framesDiffer(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) > 0.5
            || abs(lhs.minY - rhs.minY) > 0.5
            || abs(lhs.width - rhs.width) > 0.5
            || abs(lhs.height - rhs.height) > 0.5
    }
}
