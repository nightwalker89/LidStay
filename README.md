# LidStay

A lightweight native macOS desktop widget and menu bar utility for toggling `pmset -a disablesleep`, allowing your MacBook to stay awake with the lid closed even without an external monitor or AC power.

## Features

- **Desktop Widget & Menu Bar**: Borderless translucent card (`LSUIElement`) that remembers its position across launches and hides from the Dock.
- **Live Kernel State**: Reads `SleepDisabled` directly from `IOPMrootDomain` and power/battery status from `IOPSCopyPowerSourcesInfo` every 2 seconds.
- **Two Auth Modes**:
  - Uses the standard macOS administrator prompt by default.
  - Optional **1-click passwordless toggle** installs a scoped `/etc/sudoers.d/lidstay-pmset` rule (validated with `visudo -cf`) limited strictly to `/usr/bin/pmset -a disablesleep 0` and `/usr/bin/pmset -a disablesleep 1`.
- **Desktop vs. Float Layer**: Pin button switches between sitting on the desktop layer and floating above windows.
- **Low-Battery Safeguard**: Automatically restores normal sleep when battery reaches `<= 15%` on battery power (requires 1-click passwordless mode).
- **Launch at Login**: Toggleable from the menu bar via `SMAppService.mainApp`.

## Requirements

- macOS 14.0+ (Sonoma, Sequoia, Tahoe)
- Xcode / Swift 6.0+ toolchain to build from source

## Build & Install

```bash
./build.sh
open -a /Applications/LidStay.app
```

`build.sh` compiles the release binary with SwiftPM, bundles `/Applications/LidStay.app`, and applies an ad-hoc signature.

## How It Works

When enabled, LidStay runs:

```bash
/usr/bin/pmset -a disablesleep 1
```

When disabled (or on **Restore Normal Sleep & Quit**), it runs:

```bash
/usr/bin/pmset -a disablesleep 0
```

## Safety Warning

- **Thermal Risk**: Never put a closed MacBook into a bag, sleeve, or enclosed space while `disablesleep` is active, as it can overheat severely.
- **Battery Drain**: On battery power, `disablesleep = 1` keeps the system awake until drained unless the low-battery safeguard or manual toggle restores normal sleep.

## Project Structure

- `Sources/LidStay/PowerManager.swift` - IOKit state polling, power source reading, `pmset` execution, and sudoers management
- `Sources/LidStay/FloatingWidgetPanel.swift` - Borderless `NSPanel`, desktop/float window level switching, and display clamping
- `Sources/LidStay/WidgetView.swift` - SwiftUI widget card and quick settings popover
- `Sources/LidStay/AppDelegate.swift` - Menu bar item, widget lifecycle, and Launch at Login
- `Sources/LidStay/main.swift` - Accessory app entry point
- `scripts/make_icon.swift` - Generates `Resources/AppIcon.icns`
