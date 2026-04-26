import CoreGraphics

struct WidgetItemLayout {
    let columns: Int
    let itemSize: CGSize
}

struct WidgetGridMetrics {
    let defaultPanelSize = CGSize(width: 420, height: 240)
    let minimumPanelSize = CGSize(width: 250, height: 170)
    let maximumPanelSize = CGSize(width: 760, height: 520)
    let desktopCellSize = CGSize(width: 94, height: 94)
    let alignmentSnapThreshold: CGFloat = 12
    let outerPadding: CGFloat = 8
    let contentPadding: CGFloat = 14
    let itemSpacing: CGFloat = 8
    let titleAreaHeight: CGFloat = 20
    let headerSpacing: CGFloat = 6
    let headerEditorHeight: CGFloat = 32
    let sliderSectionHeight: CGFloat = 30
    let panelCornerRadius: CGFloat = 26
    let itemCornerRadius: CGFloat = 18
    let desktopInset: CGFloat = 40
    let idealItemWidth: CGFloat = 84
    let minimumItemWidth: CGFloat = 40
    let idealItemHeight: CGFloat = 94
    let minimumItemHeight: CGFloat = 56
    var panelContentInset: CGFloat { outerPadding + contentPadding }

    func clampedPanelSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, minimumPanelSize.width), maximumPanelSize.width),
            height: min(max(size.height, minimumPanelSize.height), maximumPanelSize.height)
        )
    }

    func itemLayout(for panelSize: CGSize, itemCount: Int, isEditing: Bool) -> WidgetItemLayout {
        let clampedSize = clampedPanelSize(panelSize)
        let contentWidth = max(clampedSize.width - (panelContentInset * 2), minimumItemWidth)
        let headerHeight = estimatedHeaderHeight(isEditing: isEditing)
        let contentHeight = max(
            clampedSize.height - (panelContentInset * 2) - headerHeight,
            minimumItemHeight
        )

        guard itemCount > 0 else {
            return WidgetItemLayout(
                columns: 1,
                itemSize: CGSize(width: min(contentWidth, idealItemWidth), height: idealItemHeight)
            )
        }

        let preferredColumnsLimit = max(
            1,
            Int((contentWidth + itemSpacing) / (idealItemWidth + itemSpacing))
        )

        var bestColumns = 1
        var bestSize = CGSize(width: minimumItemWidth, height: minimumItemHeight)
        var bestScore = CGFloat.leastNormalMagnitude

        for columns in 1...itemCount {
            let rows = Int(ceil(Double(itemCount) / Double(columns)))
            let totalHorizontalSpacing = CGFloat(max(columns - 1, 0)) * itemSpacing
            let totalVerticalSpacing = CGFloat(max(rows - 1, 0)) * itemSpacing
            let candidateWidth = floor((contentWidth - totalHorizontalSpacing) / CGFloat(columns))
            let candidateHeight = floor((contentHeight - totalVerticalSpacing) / CGFloat(rows))

            guard candidateWidth > 0, candidateHeight > 0 else { continue }

            let widthScore = candidateWidth / idealItemWidth
            let heightScore = candidateHeight / idealItemHeight
            let fitPenalty: CGFloat = (candidateWidth < minimumItemWidth || candidateHeight < minimumItemHeight) ? 0.6 : 1
            var score = min(widthScore, heightScore) * fitPenalty

            if rows == 1 && itemCount > preferredColumnsLimit {
                score *= 0.76
            }

            if rows >= 2 && rows <= 3 {
                score *= 1.08
            }

            if score > bestScore {
                bestScore = score
                bestColumns = columns
                bestSize = CGSize(
                    width: max(candidateWidth, 28),
                    height: max(candidateHeight, 36)
                )
            }
        }

        return WidgetItemLayout(
            columns: bestColumns,
            itemSize: bestSize
        )
    }

    func iconContainerHeight(for itemSize: CGSize) -> CGFloat {
        min(max(itemSize.height - max(itemSize.height * 0.34, 20), 24), 58)
    }

    private func estimatedHeaderHeight(isEditing: Bool) -> CGFloat {
        if isEditing {
            return titleAreaHeight + headerEditorHeight + sliderSectionHeight + 18
        }

        return titleAreaHeight + 6
    }
}
