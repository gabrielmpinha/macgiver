# Changelog

This file records documented changes from its introduction onward; it does not reconstruct earlier release history.

## 2026-09-18 — Screen text extractor

- Added a menu-bar Text Extractor action with a full-screen drag-selection overlay.
- Capture the selected display area locally, recognize text with Vision, and show the result in a small floating, selectable popup with a Copy All action.
- Added Screen Recording permission guidance, localized English/Portuguese/Spanish UI strings, geometry/OCR normalization tests, and usage/development/architecture documentation.
- Verification: XcodeGen regeneration and 46 XCTest cases passed with code signing disabled; signed manual UI verification remains to be completed on an unlocked desktop with Screen Recording permission available.

## 2026-09-17 — Application icons in the volume mixer

- Show each application's native icon in the volume mixer, resolving the running instance first and its installed bundle as a fallback.
- Keep the application icon visible while muted, and use a generic app symbol only when no icon can be resolved.
- Verification: five mixer tests and the localized panel-rendering test passed; inspected the Music icon in the rendered mixer; signed Debug build and strict code-signature verification passed.

## 2026-09-17 — Compact menu overview

- Placed battery and storage in matching 170-point square tiles side by side, keeping the quick controls and footer visible in the normal overview.
- Let the panel fit its content within the opening display's available height, with scrolling for longer details or error messages.
- Made the entire app-volume row clickable and added hover/pressed feedback to the summary buttons.
- Clarified free versus used storage and unavailable battery/storage states, with English, Portuguese, and Spanish labels.
- Verification: 43 XCTest cases passed in each supported language; localized light/dark and unavailable-state renders inspected; compact height and constrained-scroll fixtures passed; signed Debug build and strict code-signature verification passed. Live menu interaction remains unverified because macOS was locked during UI validation.

## 2026-09-17 — Per-application volume mixer

- Replaced the output-device volume panel with independent sliders and mute controls for running applications.
- Added a macOS 14.2+ Core Audio process-tap engine that applies per-app gain through a private aggregate render path, including helper-process attribution and permission guidance.
- Updated English, Portuguese, and Spanish strings, simulated provider/engine tests, app-volume usage and architecture documentation, and manual permission/audio verification steps.
- Verification: XcodeGen regeneration; English, Portuguese, and Spanish XCTest suites; signed Debug build; strict bundle code-sign verification.

## 2026-09-16 — Storage usage monitoring

- Added a compact startup-disk storage summary alongside the battery summary in the menu-bar panel.
- Added expanded storage details for used, free, and total capacity, plus interactive 15-minute, 1-hour, and 6-hour usage history.
- Added local file-system capacity reading, unavailable-value handling, English/Portuguese/Spanish strings, and deterministic storage history tests.
- Verification: XcodeGen regeneration; 38 XCTest cases passed in English, Portuguese, and Spanish with code signing disabled; signed Debug build and strict codesign verification; hosted compact, battery-detail, and storage-detail fixtures rendered.

## 2026-09-16 — Changelog-based release notes

- Generate GitHub Release descriptions from only the `CHANGELOG.md` lines added since the previous version tag.
- Fail the release workflow when no new changelog entries are available instead of publishing an unrelated or empty description.
- Verification: generated notes from the `v0.1.0` to current `CHANGELOG.md` diff and confirmed the output contains only newly added entries.

## 2026-09-16 — English, Portuguese, and Spanish localization

- Added a native String Catalog covering the complete interface, battery states, utility errors, tooltips, chart labels, and accessibility descriptions in English, Portuguese, and Spanish.
- Follow macOS language preferences and per-app language selection, including regional variants, with English fallback after relaunch. Preserve regional number formatting and plural forms.
- Allow longer utility descriptions to wrap and move the history range picker below its title so translated labels fit inside the menu panel.
- Added compiled-resource completeness checks, runtime localization tests, and deterministic AppKit-hosted view fixtures using an injectable battery reader.
- Verification: signed Debug build and strict code-signature validation; 33 XCTest cases passed for each of English/US, Portuguese/Brazil, and Spanish/Spain; 8 localization cases passed with French/France preferences and English fallback. Audited all 74 extracted catalog keys and inspected hosted-view renders for all three languages. Live menu interaction remains unverified because UI automation timed out.

## 2026-09-16 — Branch and pull request policy

- Documented the protected-`main` branch workflow, branch naming conventions, pull request requirements, CI gate, merge preference, and release boundary in `docs/development.md`.
- Verification: confirmed the policy matches the current `Swift` pull request workflow and tag-based DMG release workflow.

## 2026-09-16 — DMG release automation

- Replaced the Swift Package CI template with Xcode project build and test commands.
- Added a simple unsigned DMG packaging script and a tag-triggered GitHub Release workflow.
- Documented local DMG creation and the expected Gatekeeper warning for unsigned distribution.
- Verification: local Release build and DMG creation completed successfully; existing tests remain covered by the Xcode CI workflow.

## 2026-09-16 — Battery history cleanup

- Removed connected-device battery discovery and its optional iPhone/iPad helper from the battery panel.
- Fixed the energy-history charts so the selected time window remains stable and isolated readings remain visible while the next samples are collected.
- Verification: battery and app-state XCTest suites pass after removing device-only coverage.

## 2026-09-16 — Menu bar interface refresh

- Reworked the menu bar panel into a compact utility cockpit with a clearer header, active utility count, and native macOS material styling.
- Added distinct visual states for Keep Awake, Lock Keyboard, and Keyboard Light, including clearer unavailable and recovery states.
- Refined the battery summary and expanded battery details flow with live status, refresh controls, and more consistent cards.
- Verification: Debug build succeeded and all 30 XCTest cases passed with `CODE_SIGNING_ALLOWED=NO`.

## 2026-09-16 — Documentation refresh

- Reworked the English README around current features, requirements, build/launch commands, and daily use.
- Added usage and troubleshooting, development and verification, and architecture guides so users and contributors can find the appropriate level of detail.
- Clarified idle-sleep behavior, battery power semantics, session-only history, optional iOS helpers, and hardware-validation limits.
- Verification: reviewed behavior against source, project configuration, and test coverage; checked documentation links and command examples.
- Compatibility: documentation-only change; application behavior and configuration are unchanged.
