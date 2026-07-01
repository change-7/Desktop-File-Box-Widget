import Foundation

enum L10n {
    private static var isKorean: Bool {
        guard let languageIdentifier = Locale.preferredLanguages.first else {
            return false
        }

        return Locale(identifier: languageIdentifier).language.languageCode?.identifier == "ko"
    }

    static func text(_ english: String, _ korean: String) -> String {
        isKorean ? korean : english
    }

    static var appName: String { text("File Tray", "파일 트레이") }
    static var controlCenter: String { text("Control Center", "제어 센터") }
    static var openControlCenter: String { text("Open Control Center", "제어 센터 열기") }
    static var hideControlCenter: String { text("Hide Control Center", "제어 센터 숨기기") }
    static var quitFileTray: String { text("Quit File Tray", "파일 트레이 종료") }

    static var createEmptyWidget: String { text("Create Empty Widget", "빈 트레이 만들기") }
    static var editLayout: String { text("Edit Layout", "레이아웃 편집") }
    static var finishLayout: String { text("Finish Layout", "레이아웃 완료") }
    static var showHiddenDesktopFiles: String { text("Show Hidden Desktop Files", "숨긴 데스크탑 파일 보이기") }
    static var resumeDesktopHiding: String { text("Resume Desktop Hiding", "데스크탑 파일 숨기기 재개") }

    static var pinnedFiles: String { text("Pinned Files", "고정 파일") }
    static func pinnedFiles(_ index: Int) -> String {
        index <= 1 ? pinnedFiles : text("Pinned Files \(index)", "고정 파일 \(index)")
    }
    static func generatedPinnedFilesIndex(from title: String) -> Int? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle == "Pinned Files" || trimmedTitle == "고정 파일" {
            return 1
        }

        for prefix in ["Pinned Files ", "고정 파일 "] {
            guard trimmedTitle.hasPrefix(prefix) else { continue }
            return Int(trimmedTitle.dropFirst(prefix.count))
        }

        return nil
    }

    static var screenshots: String { text("Screenshots", "스크린샷") }
    static func isGeneratedScreenshotsTitle(_ title: String) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle == "Screenshots" || trimmedTitle == "스크린샷"
    }

    static var untitledWidget: String { text("Untitled Widget", "이름 없는 트레이") }
    static var file: String { text("File", "파일") }
    static var folder: String { text("Folder", "폴더") }

    static var images: String { text("Images", "이미지") }
    static var documents: String { text("Documents", "문서") }
    static var archives: String { text("Archives", "압축 파일") }
    static var videos: String { text("Videos", "비디오") }
    static var audio: String { text("Audio", "오디오") }
    static var folders: String { text("Folders", "폴더") }
    static var other: String { text("Other", "기타") }
    static func isGeneratedCategoryTitle(_ title: String) -> Bool {
        let generatedTitles = [
            "Images", "이미지",
            "Documents", "문서",
            "Archives", "압축 파일",
            "Videos", "비디오",
            "Audio", "오디오",
            "Folders", "폴더",
            "Other", "기타",
        ]
        return generatedTitles.contains(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static var pixels: String { text("Pixels", "픽셀") }
    static var cells: String { text("Cells", "칸") }
    static var opacity: String { text("Opacity", "투명도") }
    static var color: String { text("Color", "색상") }
    static var widgetName: String { text("Widget Name", "트레이 이름") }
    static var sizeUnit: String { text("Size Unit", "크기 단위") }
    static var useDefaultColor: String { text("Use default color", "기본 색상 사용") }

    static var viewAs: String { text("View As", "보기 방식") }
    static var icons: String { text("Icons", "아이콘") }
    static var list: String { text("List", "목록") }
    static var open: String { text("Open", "열기") }
    static var revealInFinder: String { text("Reveal in Finder", "Finder에서 보기") }
    static var moveToTrash: String { text("Move to Trash", "휴지통으로 이동") }
    static var removeFromWidget: String { text("Remove from Widget", "트레이에서 제거") }
    static var unpinFromWidget: String { text("Unpin from Widget", "트레이에서 빼기") }
    static var copyTrayItems: String { text("Copy Tray Items", "트레이 항목 복사") }
    static var copyAllScreenshots: String { text("Copy All Screenshots", "모든 스크린샷 복사") }
    static var moveAllScreenshotsToTrash: String { text("Move All Screenshots to Trash", "모든 스크린샷 휴지통으로 이동") }
    static var closeTray: String { text("Close Tray", "트레이 닫기") }
    static var dragToResize: String { text("Drag to resize", "드래그해서 크기 조절") }

    static var dropFilesHere: String { text("Drop files or folders here", "파일 또는 폴더를 여기에 놓기") }
    static var editEmptyWidgetHint: String {
        text(
            "Move the widget. Use the floating editor for size and appearance.",
            "트레이를 이동하세요. 떠 있는 편집창에서 크기와 모양을 조절할 수 있습니다."
        )
    }
    static var useEmptyWidgetHint: String {
        text(
            "Create an empty widget, then drag items from Finder to pin them here.",
            "빈 트레이를 만든 뒤 Finder에서 항목을 끌어와 여기에 고정하세요."
        )
    }

    static var controlCenterDescription: String {
        text(
            "Widgets for your desktop files, with movable file panels, Quick Look, and direct unpin controls.",
            "데스크탑 파일을 위한 트레이입니다. 파일 패널 이동, 훑어보기, 바로 빼기를 지원합니다."
        )
    }
    static func currentWidgets(_ count: Int) -> String {
        text("Current widgets: \(count)", "현재 트레이: \(count)개")
    }
    static var editModeDescription: String {
        text(
            "Edit mode is on. Drag a widget by its background to move it, type width and height directly, and remove pinned items with the minus button or Remove from Widget.",
            "편집 모드입니다. 배경을 드래그해 트레이를 이동하고, 너비와 높이를 직접 입력하며, 마이너스 버튼이나 트레이에서 제거 메뉴로 항목을 제거할 수 있습니다."
        )
    }
    static var useModeDescription: String {
        text(
            "Use mode is on. Drag files or folders from Finder into widgets, use arrow keys to move selection, press Space for Quick Look, and unpin items from the button or context menu.",
            "사용 모드입니다. Finder에서 파일이나 폴더를 트레이에 끌어 넣고, 방향키로 선택을 이동하며, Space로 훑어보고, 버튼이나 메뉴로 항목을 뺄 수 있습니다."
        )
    }

    static var desktopSafety: String { text("Desktop Safety", "데스크탑 안전") }
    static var desktopHidingPausedDescription: String {
        text(
            "Desktop file hiding is paused for this app session. Pinned files stay visible on the Desktop until hiding is resumed or the app restarts.",
            "이번 앱 실행 동안 데스크탑 파일 숨기기가 일시정지되었습니다. 숨기기를 재개하거나 앱을 다시 시작할 때까지 고정된 파일이 데스크탑에 보입니다."
        )
    }
    static var desktopHidingActiveDescription: String {
        text(
            "If hidden Desktop files ever need to be restored while the app is still running, pause hiding and show them immediately.",
            "앱 실행 중 숨겨진 데스크탑 파일을 복원해야 하면 숨기기를 일시정지해 즉시 보이게 할 수 있습니다."
        )
    }
    static func attachmentExportRetention(_ retention: String) -> String {
        text("Attachment export retention: \(retention)", "첨부 내보내기 보관 시간: \(retention)")
    }
    static var attachmentExportRetentionHelp: String {
        text(
            "Used only for hidden Desktop items dragged from File Tray into apps or browser upload areas.",
            "파일 트레이에서 앱이나 브라우저 업로드 영역으로 드래그한 숨겨진 데스크탑 항목에만 사용됩니다."
        )
    }

    static var automation: String { text("Automation", "자동화") }
    static var collectNewDesktopScreenshots: String { text("Collect new Desktop screenshots", "새 데스크탑 스크린샷 자동 수집") }
    static var organizeNewDesktopFilesByType: String { text("Organize new Desktop files by type", "새 데스크탑 파일을 종류별로 정리") }
    static var organizeNewDesktopFilesByDate: String { text("Organize new Desktop files by date", "새 데스크탑 파일을 날짜별로 정리") }
    static var dateTrayPriorityHelp: String {
        text(
            "Date trays use each file's creation date and take priority over type trays.",
            "날짜 트레이는 각 파일의 생성일을 사용하며 종류별 트레이보다 우선합니다."
        )
    }
    static var customFileTypes: String { text("Custom file types", "사용자 파일 종류") }
    static var extensionPlaceholder: String { text("Extension", "확장자") }
    static var category: String { text("Category", "분류") }
    static var add: String { text("Add", "추가") }
    static var remove: String { text("Remove", "제거") }

    static func formattedRetention(minutes: Int) -> String {
        if minutes < 60 {
            return text("\(minutes) min", "\(minutes)분")
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return text(hours == 1 ? "1 hour" : "\(hours) hours", "\(hours)시간")
        }

        return text("\(hours)h \(remainingMinutes)m", "\(hours)시간 \(remainingMinutes)분")
    }

    static var moveAllScreenshotsAlertTitle: String {
        text("Move all screenshots to Trash?", "모든 스크린샷을 휴지통으로 이동할까요?")
    }
    static var moveAllScreenshotsAlertMessage: String {
        text(
            "This will move the original files to the macOS Trash. When the tray becomes empty, File Tray removes it and will create a fresh Screenshots tray for the next screenshot.",
            "원본 파일이 macOS 휴지통으로 이동됩니다. 트레이가 비면 파일 트레이가 해당 트레이를 제거하고 다음 스크린샷이 생길 때 새 스크린샷 트레이를 만듭니다."
        )
    }
    static var cancel: String { text("Cancel", "취소") }

    static func widgetPersistenceWarning(backupName: String?) -> String {
        let englishBackup = backupName.map { " and copied a backup to \($0)" } ?? ""
        let koreanBackup = backupName.map { ", 백업을 \($0)에 복사했습니다" } ?? ""
        return text(
            "Widget state could not be loaded. File Tray preserved the current store\(englishBackup) and will not overwrite it during this session.",
            "트레이 상태를 불러올 수 없습니다. 파일 트레이는 현재 저장 파일을 보존했고\(koreanBackup), 이번 실행 중에는 덮어쓰지 않습니다."
        )
    }
}
