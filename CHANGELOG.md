# Changelog

This file records documented changes from its introduction onward; it does not reconstruct earlier release history.

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
