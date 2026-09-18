# MacGiver

> Everyday Mac utilities, one menu bar panel.

MacGiver is a native macOS app for keeping your Mac awake, locking keyboard input while cleaning, extracting text from the screen, controlling the built-in keyboard backlight, mixing application volume, and checking battery and storage information. It lives in the menu bar, with compact summaries that expand into live readings, charts, and utility controls.

## Features

| Feature | What it does |
| --- | --- |
| **Keep Awake** | Prevents idle system sleep while enabled. |
| **Lock Keyboard** | Blocks keyboard events while leaving mouse and trackpad input available. |
| **Text Extractor** | Selects an area of the screen, recognizes its text locally, and opens it in a copyable popup. |
| **Keyboard Light** | Turns the built-in backlight off and restores its previous brightness during the same app session. |
| **Mac battery** | Shows charge, charging state, time estimates, battery power, estimated health, and cycle count. |
| **Energy history** | Charts charge and battery power over 15 minutes, 1 hour, or 6 hours. |
| **Mac storage** | Shows used, free, and total space for the startup disk. |
| **Storage history** | Charts startup-disk usage over 15 minutes, 1 hour, or 6 hours. |
| **App volume mixer** | Adjusts volume and mute state independently for running applications. |

Hardware-dependent readings appear only when macOS exposes them. See the [usage guide](docs/usage.md) for support details.

The complete interface is available in **English, Portuguese, and Spanish**, including tooltips, errors, and accessibility descriptions. MacGiver follows the macOS language preference (or the language selected for the app in System Settings), with English as the fallback. Relaunch after changing the language.

## Requirements

- **To run:** macOS 13 Ventura or later. Backlight control requires a supported built-in backlit keyboard.
- **To build:** Xcode 26 or later. The project uses Swift 6 and includes an Icon Composer asset.
- **To regenerate the project:** [XcodeGen](https://github.com/yonaskolb/XcodeGen).

The macOS deployment target is 13.0; this does not guarantee every hardware integration works on every supported release. Keyboard Light uses a private macOS interface that can change between releases.

## Build and launch

With Xcode installed and selected as the active developer directory, run:

```bash
git clone https://github.com/gabrielmpinha/macgiver.git
cd macgiver

# Install XcodeGen with Homebrew if needed.
brew install xcodegen

xcodegen generate
xcodebuild \
  -project MacGiver.xcodeproj \
  -scheme MacGiver \
  -configuration Debug \
  -derivedDataPath /tmp/MacGiverDerivedData \
  build

open /tmp/MacGiverDerivedData/Build/Products/Debug/MacGiver.app
```

Build products go outside the repository to avoid signing problems caused by metadata in synced folders. The generated Xcode project is also committed, so XcodeGen is only necessary when regenerating it.

See the [development guide](docs/development.md) for Xcode setup, testing, and signing checks.

## Build a simple DMG

To create an unsigned DMG for local testing or private sharing:

```bash
xcodebuild \
  -project MacGiver.xcodeproj \
  -scheme MacGiver \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MacGiverReleaseDerivedData \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

bash scripts/create-dmg.sh \
  /tmp/MacGiverReleaseDerivedData/Build/Products/Release/MacGiver.app \
  /tmp/MacGiver.dmg
```

The DMG contains `MacGiver.app` and an **Applications** shortcut. Because it is unsigned, macOS may show a Gatekeeper warning when another person opens it. No paid Apple Developer account is needed for this simple package.

Pushing a version tag such as `vX.Y.Z` starts the [DMG release workflow](.github/workflows/release-dmg.yml), which builds the app, creates the DMG, and attaches it to a GitHub Release using GitHub's built-in token. This workflow does not sign or notarize the app.

## Usage

1. Launch MacGiver and click its menu bar icon. It does not open a regular app window or show a Dock icon.
2. Use **Keep Awake**, **Lock Keyboard**, and **Keyboard Light** independently.
3. Click the **Text Extractor** icon beside **Quick Controls**, drag over text on the screen, and wait for the extracted text popup.
4. Click **Copy All**, or select only part of the extracted text and use the normal macOS copy command.
5. Click the battery or storage summary to expand its details and history.
6. Use the **App volume** card to expand the per-application mixer. Move a slider or mute one app without changing the others.
7. Open **Settings** at the bottom of the panel to change the Text Extractor keyboard shortcut.
8. Use **Quit** at the bottom of the panel to close the app.

**Lock Keyboard** requires permission in **System Settings > Privacy & Security > Accessibility**. After enabling MacGiver there, return to the panel and try the switch again. Use your mouse or trackpad to turn the lock off.

**Text Extractor** requires **System Settings > Privacy & Security > Screen Recording** permission. MacGiver captures the selected display locally, sends the selected image to Apple's Vision text recognizer, and does not upload the screenshot or recognized text. Press **Esc** while selecting to cancel.

The Text Extractor shortcut defaults to **Command-Shift-7**. Open **Settings** or press **Command-,** to record a different shortcut. The shortcut must include Command, Control, or Option; if macOS or another app already owns the combination, MacGiver keeps the previous shortcut and reports the conflict.

Keep Awake prevents idle system sleep; it does not request that the display stay on or provide a closed-lid mode. Battery power is the flow into or out of the battery, not total Mac or wall-outlet consumption.

Storage usage reports the startup disk's used, free, and total capacity from macOS. Its history is sampled while MacGiver is running and is kept only for the current session.

For brightness behavior and common problems, see the [usage and troubleshooting guide](docs/usage.md).

## Testing

```bash
xcodebuild \
  -project MacGiver.xcodeproj \
  -scheme MacGiver \
  -configuration Debug \
  -derivedDataPath /tmp/MacGiverTestsDerivedData \
  test \
  CODE_SIGNING_ALLOWED=NO
```

Tests cover backlight state transitions, battery, storage, per-application volume state, compiled translations, language selection, plurals, regional formatting, and rendered localization fixtures. System integrations use simulated providers in unit tests; real audio changes and menu bar interaction require the [manual verification steps](docs/development.md#hardware-and-ui-verification).

## Tech stack

| Technology | Role |
| --- | --- |
| Swift 6 | Application code and concurrency |
| SwiftUI and AppKit | Menu bar UI, application lifecycle, and wake notifications |
| Swift Charts | Interactive battery and storage history |
| Xcode String Catalogs | English, Portuguese, and Spanish localization with native language selection |
| IOKit | Sleep prevention and Mac power-source data |
| Core Graphics and Accessibility | Keyboard event interception and permission checks |
| Vision | Local OCR for the Text Extractor |
| CoreAudio | Process taps, per-application gain/mute, and private aggregate-device rendering |
| CoreBrightness (private, loaded at runtime) | Built-in keyboard backlight control |
| XcodeGen and XCTest | Project generation and automated tests |

## Documentation

- [Documentation index](docs/README.md) — find the guide for your task.
- [Usage and troubleshooting](docs/usage.md) — controls, permissions, battery readings, and common problems.
- [Development and verification](docs/development.md) — build, test, and validate changes.
- [Architecture and source map](docs/architecture.md) — components, data flow, and integration limits.
- [Changelog](CHANGELOG.md) — documented changes.

## License

[MIT](LICENSE) © 2026 Gabriel Pinheiro.
