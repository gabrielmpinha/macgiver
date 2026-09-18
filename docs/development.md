# Development and verification

[Documentation index](README.md) · [Architecture](architecture.md)

## Project setup

Use Xcode 26 or later, Swift 6, and macOS. The deployment target is macOS 13.0. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you need to regenerate the project.

Confirm the selected developer tools:

```bash
xcodebuild -version
xcode-select -p
```

The developer directory must point to a full Xcode installation. If it points to Command Line Tools, select the intended Xcode installation in **Xcode > Settings > Locations > Command Line Tools**.

[project.yml](../project.yml) defines the application and test targets, build settings, sources, resources, and shared scheme. [MacGiver.xcodeproj](../MacGiver.xcodeproj) is the committed generated project.

From the repository root:

```bash
brew install xcodegen
xcodegen generate
open MacGiver.xcodeproj
```

In Xcode, select the **MacGiver** scheme and **My Mac** destination, then run. Regenerate the project after changing its specification or adding/removing source files. Review generated changes alongside the specification.

## Command-line build

```bash
xcodebuild \
  -project MacGiver.xcodeproj \
  -scheme MacGiver \
  -configuration Debug \
  -derivedDataPath /tmp/MacGiverDerivedData \
  build

codesign --verify --deep --strict \
  /tmp/MacGiverDerivedData/Build/Products/Debug/MacGiver.app

open /tmp/MacGiverDerivedData/Build/Products/Debug/MacGiver.app
```

An external DerivedData directory keeps artifacts out of the checkout and avoids signing issues associated with synced-folder metadata. The project also normalizes app-bundle metadata before signing.

A locally built app is not a notarized distribution artifact. Keyboard Light depends on a private framework and is not appropriate for Mac App Store submission.

## DMG release

The repository includes `scripts/create-dmg.sh` for creating a simple unsigned DMG. It packages the Release `.app` with an **Applications** shortcut and does not require an Apple Developer account. An unsigned download may trigger a Gatekeeper warning on another Mac.

GitHub Actions creates a DMG release when a `v*` tag is pushed. For example, after committing a release-ready change:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

The workflow publishes the DMG to a GitHub Release with a description containing only the lines added to `CHANGELOG.md` since the previous version tag. It fails if no changelog entries were added, so a release cannot silently receive an unrelated or empty description. Developer ID signing and notarization are intentionally outside this simple release path.

## Automated tests

```bash
xcodebuild \
  -project MacGiver.xcodeproj \
  -scheme MacGiver \
  -configuration Debug \
  -derivedDataPath /tmp/MacGiverTestsDerivedData \
  test \
  CODE_SIGNING_ALLOWED=NO
```

Use a separate test DerivedData directory so the unsigned XCTest host does not replace the app used for signed manual validation. Tests disable signing because XCTest adds temporary bundles and frameworks to the host application.

| Test file | Coverage |
| --- | --- |
| [AppStateTests.swift](../Tests/MacGiverTests/AppStateTests.swift) | Initial menu state, brightness restoration, initially dark keyboards, external changes, failed writes, readback confirmation, invalid readings, and retries. |
| [BatteryTests.swift](../Tests/MacGiverTests/BatteryTests.swift) | Apple Silicon/Intel decoding fixtures, charge states, unavailable values, bounded history, and sleep gaps. |
| [StorageTests.swift](../Tests/MacGiverTests/StorageTests.swift) | Capacity decoding, invalid values, byte formatting, bounded history, and sleep gaps. |

Backlight tests inject simulated reads and writes; they do not establish hardware compatibility. Device parser fixtures also do not prove that a particular accessory or OS release publishes the expected values.

## Hardware and UI verification

Use the signed application on real hardware for changes to system integrations or menu behavior.

| Area | Verification |
| --- | --- |
| Menu bar | Launch, open and close the panel, expand battery and storage details, collapse them, then reopen. Confirm the compact state returns and expanded content scrolls. |
| Keep Awake | Enable and disable the switch; use `pmset -g assertions` to check that the MacGiver idle-sleep assertion appears and is released. |
| Keyboard lock | Grant Accessibility access, enable the lock, verify keyboard input is blocked, and use the mouse/trackpad to disable it. |
| Backlight | Start with visible light, turn it off, and turn it on again. Check the actual keys and restored brightness; also test an initially dark keyboard and external brightness changes while the panel is open. |
| Mac battery | Compare state and available estimates with `pmset -g batt`. Test charging, discharge, unavailable fields, and sleep/wake history gaps. |
| Energy history | Open battery details, confirm the current point appears, wait for another sample, switch between 15m/1h/6h, and verify the chart remains readable across gaps. |
| Mac storage | Compare used and free values with Finder's startup-disk information. Confirm unavailable values render as a clear state if the file-system attributes cannot be read. |
| Storage history | Open storage details, confirm the current usage point appears, wait for another sample, switch between 15m/1h/6h, and verify the chart remains readable across gaps. |
| App volume mixer | Launch the signed app on macOS 14.2+, open the panel, allow System Audio Recording when prompted, open the app mixer, move one app slider, mute/unmute it, and verify a second app is unaffected. |
| Application refresh | Start and stop an audio-producing app or its helper process while the panel is open, then use **Refresh applications** and confirm the app row and PLAYING/AVAILABLE state update. |
| Text extractor | Launch the signed app, allow Screen Recording when prompted, click the text-viewfinder icon, drag over readable text, confirm the popup contains selectable OCR text, and verify **Copy All** updates the clipboard. Press **Esc** to cancel a second selection. |

Record the Mac model, macOS version, device models, and observed results when reporting hardware validation. A successful build, deployment target, or passing fixture test is not evidence of broad hardware compatibility.

## Build troubleshooting

- **Wrong developer directory:** verify `xcode-select -p` and select the full Xcode installation.
- **Missing or outdated generated files:** run `xcodegen generate` from the repository root and inspect the generated diff.
- **Signing rejects resource forks or Finder metadata:** use the external DerivedData path shown above and check that the project's metadata-normalization build phase runs.
- **The app fails signature verification after testing:** rebuild without `CODE_SIGNING_ALLOWED=NO`, using the normal build directory.
- **A system control fails at runtime:** consult [usage troubleshooting](usage.md#troubleshooting) and validate the signed app on the affected hardware.

## Documentation and contributions

Run the relevant verification before committing. Commits use English Conventional Commits with a scope; non-trivial changes include an explanatory body.

When behavior changes, update the matching guide and source-map entry, and append an entry to [CHANGELOG.md](../CHANGELOG.md).

## Branches and pull requests

- Treat `main` as the protected integration branch. Do not develop directly on `main`.
- Create one short-lived branch per focused change from an up-to-date `main`.
- Use descriptive branch names with one of these prefixes: `feat/`, `fix/`, `docs/`, `refactor/`, `test/`, `build/`, or `chore/`.
- Keep each branch limited to one logical outcome; do not mix unrelated cleanup or generated artifacts into the change.
- Open a pull request targeting `main` for every branch, including documentation, build, and repository changes.
- Use a concise Conventional Commit-style pull request title, such as `feat(menu-bar): add utility status summary`.
- Describe the motivation, important implementation details, user-visible impact, and verification performed in the pull request body.
- Do not merge until the `Swift` GitHub Actions workflow passes its build and XCTest jobs and any requested review is resolved.
- Prefer squash merging to keep `main`'s history focused. Delete the branch after merge.
- Create release tags only from `main`; do not publish release artifacts from feature branches.
