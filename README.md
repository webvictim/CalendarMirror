# CalendarMirror

A macOS menu bar app that mirrors busy events from one Apple Calendar to another. Useful for blocking time across multiple calendar accounts (e.g. mirroring your personal calendar's busy slots into your work calendar).

## Features

- **Menu bar app** — runs in the background with no Dock icon; configuration window opens on demand
- **Auto-sync** — configurable interval (minutes/hours/days) with wake-from-sleep catch-up
- **Title modes** — copy the original event title, or rewrite all mirrored events with a custom title
- **Dry run** — preview what would change without modifying any calendars
- **Launch at login** — optional, uses macOS native login items
- **Smart matching** — tracks mirrored events via a tag in the notes field, so it can update or delete stale mirrors without duplicating

## Prerequisites

- macOS 15.7 or later
- Xcode 16+ (for building from source)
- Full calendar access (the app will prompt on first launch)

## Installation

### From source

```bash
git clone https://github.com/webvictim/CalendarMirror
cd CalendarMirror
./build.sh
```

This builds a Release configuration and installs to `/Applications/CalendarMirror.app`.

### Manual Xcode build

1. Open `CalendarMirror.xcodeproj` in Xcode
2. Select the CalendarMirror scheme, set to Release
3. Product → Build (Cmd+B)
4. Copy the built `.app` from DerivedData to `/Applications`

## Usage

1. Launch CalendarMirror — it appears in the menu bar (two-calendar icon)
2. Click the menu bar icon → **Open Window** to configure
3. Select a **Source** calendar (events to mirror from) and **Target** calendar (where mirrors are created)
4. Choose title mode: copy original titles or rewrite with a custom string
5. Set lookback/lookahead days to control the date range
6. Optionally enable **Auto-sync** with your preferred interval
7. Click **Sync Now** (or **Start** if auto-sync is enabled)

### Menu bar dropdown

- **Last sync** time and event count summary
- **Sync Now** — trigger an immediate sync (greyed out if dry run is on)
- **Open Window** — show the configuration window
- **Quit** — exit the app

### How mirroring works

- Only events marked as "busy" are mirrored (free/available events are skipped)
- Each mirrored event is tagged in its notes field with `[MIRROR srcUID=<id>]`
- On each sync: new events are created, changed events are updated, and events that no longer exist in the source are deleted from the target
- All changes are batched in a single EventKit commit

## Build script

The included `build.sh` script:

```bash
./build.sh          # Build Release and install to /Applications
./build.sh debug    # Build Debug only (no install)
```

## Uninstall

1. Quit CalendarMirror from the menu bar
2. Delete `/Applications/CalendarMirror.app`
3. Optionally remove preferences: `defaults delete net.webvictim.calendarmirror`
