import AppKit
import CoreGraphics

@MainActor
final class SystemWidgetReservationService {
    static let shared = SystemWidgetReservationService()

    private let notificationCenterBundleID = "com.apple.notificationcenterui"
    private let reservedInset: CGFloat = 10

    private init() {}

    func reservedFrames(on screen: NSScreen) -> [CGRect] {
        let targetScreenID = screenIdentifier(for: screen)
        let notificationCenterPIDs = Set(
            NSRunningApplication
                .runningApplications(withBundleIdentifier: notificationCenterBundleID)
                .map(\.processIdentifier)
        )
        guard !notificationCenterPIDs.isEmpty else { return [] }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

        return windowList.compactMap { windowInfo in
            guard isDesktopWidgetWindow(windowInfo, notificationCenterPIDs: notificationCenterPIDs),
                  let rawBounds = windowBounds(from: windowInfo),
                  let resolvedWindow = resolvedWindowFrame(for: rawBounds),
                  resolvedWindow.screenID == targetScreenID else {
                return nil
            }

            // Keep a small exclusion zone around the real system widget frame,
            // but do not expand it enough to make nearby manual placement jittery.
            return resolvedWindow.frame.insetBy(dx: reservedInset, dy: reservedInset)
        }
    }

    private func isDesktopWidgetWindow(
        _ windowInfo: [String: Any],
        notificationCenterPIDs: Set<pid_t>
    ) -> Bool {
        guard let ownerPIDNumber = windowInfo[kCGWindowOwnerPID as String] as? NSNumber else {
            return false
        }
        guard notificationCenterPIDs.contains(ownerPIDNumber.int32Value) else {
            return false
        }

        let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0.01 else {
            return false
        }

        let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        guard layer < 0 else {
            return false
        }

        guard let bounds = windowBounds(from: windowInfo) else {
            return false
        }

        return bounds.width >= 120 && bounds.height >= 120
    }

    private func windowBounds(from windowInfo: [String: Any]) -> CGRect? {
        guard let boundsDictionary = windowInfo[kCGWindowBounds as String] else {
            return nil
        }

        return CGRect(dictionaryRepresentation: boundsDictionary as! CFDictionary)
    }

    private func resolvedWindowFrame(for rawBounds: CGRect) -> ResolvedWidgetWindow? {
        let candidates = NSScreen.screens.compactMap { screen -> ResolvedWidgetWindow? in
            guard let displayBounds = quartzDisplayBounds(for: screen) else {
                return nil
            }

            let quartzIntersection = rawBounds.intersection(displayBounds)
            guard !quartzIntersection.isNull, !quartzIntersection.isEmpty else {
                return nil
            }

            let convertedBounds = convertToAppKitCoordinates(rawBounds, on: screen, displayBounds: displayBounds)
            let intersection = convertedBounds.intersection(screen.visibleFrame)
            guard !intersection.isNull, !intersection.isEmpty else {
                return nil
            }

            return ResolvedWidgetWindow(
                screenID: screenIdentifier(for: screen),
                frame: convertedBounds,
                visibleIntersectionArea: intersection.width * intersection.height
            )
        }

        return candidates.max { lhs, rhs in
            lhs.visibleIntersectionArea < rhs.visibleIntersectionArea
        }
    }

    private func convertToAppKitCoordinates(
        _ rawBounds: CGRect,
        on screen: NSScreen,
        displayBounds: CGRect
    ) -> CGRect {
        let localQuartzMaxY = rawBounds.maxY - displayBounds.minY

        return CGRect(
            x: rawBounds.minX,
            y: screen.frame.minY + displayBounds.height - localQuartzMaxY,
            width: rawBounds.width,
            height: rawBounds.height
        )
    }

    private func quartzDisplayBounds(for screen: NSScreen) -> CGRect? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    }

    private func screenIdentifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }

        let origin = screen.frame.origin
        let size = screen.frame.size
        return "\(Int(origin.x)):\(Int(origin.y)):\(Int(size.width)):\(Int(size.height))"
    }
}

private struct ResolvedWidgetWindow {
    let screenID: String
    let frame: CGRect
    let visibleIntersectionArea: CGFloat
}
