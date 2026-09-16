# MacGiver

> Lightweight macOS utilities that live in your menu bar.

MacGiver gives you quick access to focused tools for everyday Mac workflows, without keeping a full application window open.

## Features

- **Keep Awake** — prevents the Mac from going to sleep while enabled.
- **Lock Keyboard** — blocks keyboard input while you clean the keys.
- **Keyboard Light** — turns the built-in keyboard backlight on or off and restores its previous brightness.
- **Battery panel** — live battery power, estimated time remaining, health, and cycle count, with interactive charge and power graphs inside the menu bar.
- **Connected batteries** — available Bluetooth accessory and USB device levels, including separate AirPods components and optional iPhone/iPad support.
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

Use **Keyboard Light** to turn the built-in keyboard backlight off. Turning it back on restores the brightness captured before turning it off during this app session. If the keyboard starts dark, turning it on uses 50% brightness. The switch reads the current brightness when opened and follows changes while the panel is visible.

MacGiver uses the private macOS CoreBrightness framework, loaded at runtime with method-signature checks. It targets the built-in keyboard and confirms writes by reading the brightness back. Automatic-brightness and idle-dimming preferences are not changed, but this manual override can take precedence over automatic adjustment while the app is running. A future macOS update can change this private interface, and it is not suitable for Mac App Store distribution. If a reading fails, the control shows an error with a retry button.

### Battery panel

Open MacGiver from the menu bar to see a compact battery summary inside the existing utility interface. Click the summary to expand the full battery view in the same popover; click the chevron to collapse it again. It shows:

- Charge level and macOS estimates for time until empty or until full. When macOS has no estimate, the dashboard shows “Estimating…”. A paused charge and a full battery are displayed separately.
- Live **battery power** in watts, sampled every five seconds. This is power entering or leaving the battery, not total Mac or wall-outlet consumption. The power graph uses positive values for discharge and negative values for charge, independently of whether a charger is connected.
- Estimated health relative to design capacity and the reported total cycle count. Health uses nominal/raw capacities, not the normalized charge percentage, and may differ from the value in System Settings.
- Charge and power graphs with 15-minute, one-hour, and six-hour ranges. Hover over a graph to inspect a reading. History begins at launch and is kept in memory for up to six hours. Quitting clears it. Gaps and unavailable measurements are not interpolated.

The app reads macOS power-source descriptions and AppleSmartBattery registry properties. These hardware properties vary by Mac and OS release. Missing fields are shown as unavailable; desktop Macs can still view connected devices.

### Connected devices

The expanded menu panel refreshes device readings once a minute while open, with a manual refresh button. Bluetooth devices appear only when macOS reports them as connected; disconnected cached levels are excluded. AirPods can report separate left, right, and case levels. USB HID accessories appear when they publish a battery percentage.

USB iPhones and iPads are detected without extra software. To enable battery-level and charging-status queries, optionally install [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice):

```bash
brew install libimobiledevice
```

MacGiver looks for `ideviceinfo` in `/opt/homebrew/bin` and `/usr/local/bin`. Plug in the device, unlock it, and trust this Mac in Finder. Queries use a simple connection that avoids automatic pairing, and are bounded by a timeout. Some iOS versions may not expose a reading over this connection.

Apple Watch battery details, accessory health/cycle counts, and accessory time remaining are not available through these sources. A device that does not publish its battery level displays “Battery level not reported.” The information button in the menu panel explains device support and setup. No extra software is installed automatically.

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

Battery tests cover Apple Silicon and Intel capacity/current formats, charging and paused-charge states, unknown readings, short wake events, history retention, device parsing, and command timeout/cancellation/output limits. Mac telemetry was checked live against `pmset`; connected-device parsing uses fixtures and still requires hardware verification with each accessory or iOS version. The dashboard and menu views were visually checked in a temporary native host, including opening, closing, and reopening the dashboard. The actual menu-bar-only activation path and older macOS releases require separate runtime validation.

Unit tests use a simulated backlight and do not change hardware. To check hardware support, run the signed app on a MacBook with the light on, switch **Keyboard Light** off, verify the keys go dark, and switch it on again to verify the previous brightness returns. Also check starting with the light off and changing brightness in System Settings while the panel is open. Hardware readback was verified on a MacBook Air running macOS 27.0; older releases require separate validation.

## Tech stack

| Technology | Purpose |
| --- | --- |
| Swift 6 | Application code and system integrations |
| SwiftUI | Menu bar interface and controls |
| AppKit | macOS application lifecycle and menu bar integration |
| IOKit Power Management | Preventing idle system sleep |
| IOKit Power Sources & IORegistry | Live Mac and USB accessory battery readings |
| Swift Charts | Interactive charge and battery power history |
| Core Graphics Event Tap | Intercepting keyboard events |
| XcodeGen | Reproducible Xcode project generation |
| XCTest | Unit testing |

## Project structure

```text
Sources/MacGiver/
├── AppState.swift       # application state and system integrations
├── BatteryReading.swift # hardware decoding and bounded history
├── BatteryMonitor.swift # app-lifetime battery sampling
├── BatteryMenuPanel.swift # compact battery panel, charts, and device readings
├── DeviceBatteryReader.swift # connected batteries and optional iOS helper
├── KeyboardBacklight.swift # CoreBrightness control and verified on/off transitions
├── MacGiverApp.swift    # app entry point and menu bar scene
└── MenuBarView.swift    # menu bar interface
Tests/MacGiverTests/     # unit tests
project.yml              # XcodeGen project definition
```

## License

This project is licensed under the MIT License.
