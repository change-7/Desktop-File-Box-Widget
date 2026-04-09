# Desktop File Box Widget

Desktop File Box Widget is a macOS desktop utility that lets you group files and folders into movable desktop widgets without deleting them.

## What It Does

- Creates desktop widgets that live above the desktop icon layer
- Lets you drag files and folders from Finder into each widget
- Opens pinned items with a double click
- Supports keyboard selection, arrow-key navigation, and Quick Look with `Space`
- Hides pinned Desktop items while the app is running and restores them when the app exits
- Recovers hidden Desktop items after an interrupted session
- Persists widget titles, positions, sizes, opacity, and pinned items between launches

## Requirements

- macOS 14 or later
- Apple Silicon build workflow is currently used in this repository

## Build

### SwiftPM build

```bash
swift build
```

### Build the `.app` bundle

```bash
./Scripts/build-app.sh
```

The packaged app is created at:

```text
dist/Desktop File Box Widget.app
```

## Usage

1. Launch `Desktop File Box Widget.app`
2. Create or select a widget from the menu bar
3. Drag files or folders from Finder into a widget
4. Double click an item to open it
5. Click once to select an item, then use:
   - `Arrow keys` to move selection
   - `Space` to toggle Quick Look
   - `Return` to open the selected item
6. Toggle edit mode to rename widgets, change opacity, move widgets, and enter widget size values

## Release Asset

The first GitHub release is tagged as `v0.1.0`.

## Project Structure

```text
Sources/FileWidgetsApp        Main macOS app target
Sources/FileWidgetsSupport    Shared support code for desktop visibility state
Sources/VisibilityGuardian    Helper process that restores hidden Desktop items after abnormal termination
Scripts/build-app.sh          App bundle packaging script
```

## Current Notes

- The app is designed around desktop organization, not file relocation
- Pinned items from the Desktop are hidden while the app is active instead of being moved
- The helper process is included in the app bundle to restore hidden Desktop items if the main app exits unexpectedly
