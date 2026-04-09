import AppKit
import Foundation

let rootPath = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
let iconsetURL = rootURL.appendingPathComponent("AppResources/AppIcon.iconset", isDirectory: true)
let outputURL = rootURL.appendingPathComponent("AppResources/AppIcon.icns", isDirectory: false)

let iconDefinitions: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let fileManager = FileManager.default
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for icon in iconDefinitions {
    let symbolImage = try renderSymbolImage(size: icon.size)
    guard let tiffRepresentation = symbolImage.tiffRepresentation,
          let bitmapRepresentation = NSBitmapImageRep(data: tiffRepresentation),
          let pngData = bitmapRepresentation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateAppIcon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to render \(icon.name)",
        ])
    }

    try pngData.write(to: iconsetURL.appendingPathComponent(icon.name), options: .atomic)
}

func renderSymbolImage(size: CGFloat) throws -> NSImage {
    guard let baseSymbol = NSImage(
        systemSymbolName: "folder.badge.plus",
        accessibilityDescription: nil
    ) else {
        throw NSError(domain: "GenerateAppIcon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Unable to load folder.badge.plus symbol",
        ])
    }

    let configuration = NSImage.SymbolConfiguration(
        pointSize: size * 0.72,
        weight: .regular
    )
    let configuredSymbol = baseSymbol.withSymbolConfiguration(configuration) ?? baseSymbol
    configuredSymbol.isTemplate = false

    let canvas = NSImage(size: NSSize(width: size, height: size))
    canvas.lockFocus()
    defer { canvas.unlockFocus() }

    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

    let symbolRect = NSRect(
        x: (size - (size * 0.72)) / 2,
        y: (size - (size * 0.72)) / 2,
        width: size * 0.72,
        height: size * 0.72
    )

    configuredSymbol.draw(
        in: symbolRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )

    return canvas
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", outputURL.path, iconsetURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "GenerateAppIcon", code: Int(process.terminationStatus), userInfo: [
        NSLocalizedDescriptionKey: "iconutil failed with status \(process.terminationStatus)",
    ])
}
