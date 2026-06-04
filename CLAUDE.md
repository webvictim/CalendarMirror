# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

This is a macOS SwiftUI app built with Xcode. Open `CalendarMirror.xcodeproj` and build/run from there, or use:

```bash
xcodebuild -project CalendarMirror.xcodeproj -scheme CalendarMirror -configuration Debug build
```

No package manager dependencies. Deployment target is macOS 15.7, Swift 5.

## Architecture

CalendarMirror is a single-window macOS app that mirrors busy events from one Apple Calendar to another. It uses EventKit to read/write calendar events.

**Key files:**

- `CalendarMirror/CalendarMirrorApp.swift` — App entry point (`MirrorBusyApp`)
- `CalendarMirror/MirrorViewModel.swift` — All business logic: calendar access, event mirroring, logging
- `CalendarMirror/ContentView.swift` — SwiftUI UI with calendar pickers, config fields, run button, and log
- `CalendarMirror/LogTextView.swift` — `NSViewRepresentable` wrapping `NSTextView` for scrollable monospace log output

**How mirroring works:**

1. User selects a source and target calendar, configures lookback/lookahead days and a mirror title
2. `MirrorViewModel.runMirror()` queries source events in the date range, skipping free-availability events
3. For each source event, it looks for an existing mirror in the target calendar by matching a tag in the notes field (`[MIRROR srcUID=<calendarItemIdentifier>]`)
4. Creates new mirrors, updates changed ones, and deletes stale mirrors that no longer have a source event
5. All changes are batched and committed in a single `store.commit()` call

**Entitlements:** Requires `NSCalendarsFullAccessUsageDescription` (in `Info.plist` at project root) for EventKit read/write access.
