# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

This is a macOS SwiftUI menu bar app built with Xcode. No package manager dependencies. Deployment target is macOS 15.7, Swift 5.

```bash
# Debug build
xcodebuild -project CalendarMirror.xcodeproj -scheme CalendarMirror -configuration Debug build

# Release build + install to /Applications
./build.sh
```

## Architecture

CalendarMirror is a menu bar macOS app that mirrors busy events from one Apple Calendar to another. It uses EventKit for calendar access, ServiceManagement for launch-at-login, and runs as an accessory app (no Dock icon) with a configuration window available on demand.

**Key files:**

- `CalendarMirror/CalendarMirrorApp.swift` — App entry point (`CalendarMirrorApp`), `MenuBarExtra` scene, `AppDelegate` for activation policy switching (accessory ↔ regular based on window visibility), `MenuBarView` for the dropdown menu
- `CalendarMirror/MirrorViewModel.swift` — All business logic: calendar access, event mirroring, auto-sync timer, wake-from-sleep sync, settings persistence (UserDefaults), source event counting. Also defines `SyncIntervalUnit` and `TitleMode` enums.
- `CalendarMirror/ContentView.swift` — SwiftUI Form-based UI with grouped sections (Calendars, Mirror Settings, Sync Schedule), collapsible log panel, app icon header with version
- `CalendarMirror/LogTextView.swift` — `NSViewRepresentable` wrapping `NSTextView` for scrollable monospace log output

**App lifecycle:**

- Starts as `.accessory` (no Dock icon, no app menu bar)
- `MenuBarExtra` provides the persistent menu bar icon and dropdown
- `Window` scene (id: "main") is the config window, opened via "Open Window" in the dropdown
- When the window becomes key → switches to `.regular` (Dock icon + app menu appear)
- When the window closes → switches back to `.accessory`
- On launch, any auto-opened window is immediately closed so the app starts silently

**How mirroring works:**

1. User selects a source and target calendar, configures lookback/lookahead days and title mode
2. `MirrorViewModel.runMirror()` queries source events in the date range, skipping free-availability events
3. For each source event, it looks for an existing mirror in the target calendar by matching a tag in the notes field (`[MIRROR srcUID=<calendarItemIdentifier>]`)
4. Creates new mirrors, updates changed ones, and deletes stale mirrors that no longer have a source event
5. All changes are batched and committed in a single `store.commit()` call
6. Title is either copied from the source event or rewritten with a custom string, based on `titleMode`

**Auto-sync:**

- Timer-based (`Timer.scheduledTimer`), interval configured as value + unit (minutes/hours/days)
- Timer doesn't fire during sleep; `NSWorkspace.didWakeNotification` triggers a catch-up sync if overdue
- Disabled when dry run is on; first manual sync starts the timer

**Settings persistence:** All user preferences stored in UserDefaults via `didSet` observers on `@Published` properties.

**Entitlements:** Requires `NSCalendarsFullAccessUsageDescription` (in `Info.plist` at project root) for EventKit read/write access.
