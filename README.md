# MacGiver

> Lightweight macOS utilities that live in your menu bar.

MacGiver gives you quick access to focused tools for everyday Mac workflows, without keeping a full application window open.

## Features

- **Keep Awake** — prevents the Mac from going to sleep while enabled.
- **Lock Keyboard** — blocks keyboard input while you clean the keys.
- **Keyboard Light** — turns the built-in keyboard backlight on or off and restores its previous brightness.
- **Menu bar controls** — enable or disable each utility from a single menu bar panel.
- **Safe recovery** — mouse input remains available so keyboard locking can always be turned off.

## Requirements

- macOS 13 Ventura or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Usage

Launch MacGiver and open it from the menu bar.

### Keep Awake

Turn on **Keep Awake** to prevent idle system sleep. Turn it off when you want macOS to return to its normal sleep behavior.

### Lock Keyboard

Turn on **Lock Keyboard** before cleaning your keyboard. On first use, macOS will request Accessibility permission:

1. Open **System Settings > Privacy & Security > Accessibility**.
2. Enable MacGiver in the list of authorized apps.
3. Return to the menu bar and enable **Lock Keyboard** again.

The lock affects keyboard events only. Mouse input remains available so you can disable the feature.

### Keyboard Light

Use **Keyboard Light** to turn the built-in keyboard backlight off temporarily. Turning it back on restores the brightness that was active before it was disabled. This control is available on Macs whose keyboard exposes the standard Apple HID backlight service.

## Build from source

Install XcodeGen if needed:

```bash
brew install xcodegen
```

Generate the Xcode project and build the app:

```bash
xcodegen generate
xcodebuild \
  -project MacGiver.xcodeproj \
  -scheme MacGiver \
  -configuration Debug \
  -derivedDataPath /tmp/MacGiverDerivedData \
  build
```

The example uses `/tmp` for build artifacts so Xcode signs the app outside synced or file-provider folders. The built app is placed at:

```text
/tmp/MacGiverDerivedData/Build/Products/Debug/MacGiver.app
```

## Testing

```bash
xcodebuild \
  -project MacGiver.xcodeproj \
  -scheme MacGiver \
  -configuration Debug \
  -derivedDataPath /tmp/MacGiverDerivedData \
  test \
  CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` is used for tests because XCTest injects temporary bundles and frameworks into the host app. Normal app builds remain locally signed by Xcode.

## Tech stack

| Technology | Purpose |
| --- | --- |
| Swift 6 | Application code and system integrations |
| SwiftUI | Menu bar interface and controls |
| AppKit | macOS application lifecycle and menu bar integration |
| IOKit Power Management | Preventing idle system sleep |
| Core Graphics Event Tap | Intercepting keyboard events |
| XcodeGen | Reproducible Xcode project generation |
| XCTest | Unit testing |

## Project structure

```text
Sources/MacGiver/
├── AppState.swift       # application state and system integrations
├── MacGiverApp.swift    # app entry point and menu bar scene
└── MenuBarView.swift    # menu bar interface
Tests/MacGiverTests/     # unit tests
project.yml              # XcodeGen project definition
```

## License

This project is licensed under the MIT License.
