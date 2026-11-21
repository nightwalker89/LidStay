# Changelog

All notable changes to LidStay are documented in this file.

## [1.1.0] - 2026-11-21

### Added
- Bilingual UI (`Auto` / `EN` / `VI`) with language switcher in widget settings (`Localization.swift`).
- `LaunchAgent` startup option (`~/Library/LaunchAgents/com.nightwalker89.LidStay.plist`) in both widget settings and menu bar.
- Single-instance enforcement via `flock`, `NSRunningApplication`, and `LSMultipleInstancesProhibited`, revealing the existing widget on relaunch.
- Bilingual `README.md` and `README.vi.md` with localized widget preview images.

## [1.0.0] - 2026-11-21

### Added
- Native SwiftUI desktop widget and menu bar utility for toggling `pmset -a disablesleep`.
- Live kernel `SleepDisabled` and battery/AC status polling via IOKit.
- Optional 1-click passwordless mode with `visudo`-validated `/etc/sudoers.d/lidstay-pmset` rule.
- Desktop vs. Float window layer pin toggle, low-battery (`<= 15%`) auto-restore, and Universal macOS GitHub Actions release workflow.
