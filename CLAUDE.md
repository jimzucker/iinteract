# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iInteract: i Feel, i Speak is a UIKit-based iOS/watchOS/macOS communication board app for children with special needs. It displays picture+audio interaction panels that speak when tapped. Available on the App Store (id363448448).

- **Version**: 2.1.0 | **License**: Mozilla Public License v2.0
- **Targets**: iOS 17.4+, watchOS 10.4+, macOS (Catalyst)
- **Language**: Swift 4.2 (SWIFT_VERSION = 4.2), UIKit, Storyboard-based UI (no SwiftUI)
- **No external dependencies** (no CocoaPods, no SPM)

## Build Commands

```bash
# Build iOS app (simulator)
xcodebuild -scheme iInteract -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run unit tests
xcodebuild -scheme iInteract -destination 'platform=iOS Simulator,name=iPhone 16' test

# Build for release
xcodebuild -scheme iInteract -configuration Release build
```

Open `iInteract.xcodeproj` in Xcode for GUI development and device testing.

## Architecture

### Data Layer
- **`panels.plist`** — Static data file defining 7 communication panels (e.g., "I feel", "I need", "I want to"), each with 3–4 interactions containing image name and audio filename references.
- **`Panel.swift`** — Model loaded from `panels.plist`; holds array of `Interaction` objects.
- **`Interaction.swift`** — Model for a single board item (image + audio pair).
- Voice preference (boy/girl) stored in `UserDefaults` via `Settings.bundle`.

### iOS App Flow
- `FeelingTableViewController` — Master list; loads all `Panel` objects from `panels.plist`, displays in a `UITableView`.
- `FeelingTableViewCell` — Custom cell for each panel row.
- `PanelViewController` — Detail view; shows the 3–4 `Interaction` images for a selected panel. Tap gesture triggers image animation + `AVFoundation` audio playback of the corresponding `sounds/` MP3 (boy_* or girl_* variant based on `UserDefaults`).

### watchOS Extension
- `InterfaceController` → `PanelController` → `InteractionInterfaceController` mirrors the iOS navigation hierarchy.
- Watch data driven by `events.plist` and `Event.swift`.

### Key Resources
- `iInteract/sounds/` — MP3 files named `boy_<name>.mp3` / `girl_<name>.mp3`
- `iInteract/Assets.xcassets/` — All interaction images and app icons
- `Settings.bundle/` — Exposes voice preference to iOS Settings app

## Upcoming Work (v2.0)
The planned v2.0 feature is user-configurable panels: users will be able to add their own pictures and record their own sounds. The UI pattern for this is modeled after the iOS Clock (alarm arrangement), profile picture selection, and Messages (audio recording). No v2.0 code is merged yet.
