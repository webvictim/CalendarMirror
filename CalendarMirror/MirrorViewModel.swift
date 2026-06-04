//
//  MirrorViewModel.swift
//  CalendarMirror
//
//  Created by Gus on 14/11/2025.
//

import SwiftUI
import EventKit
import Combine
import ServiceManagement

enum SyncIntervalUnit: String, CaseIterable {
    case minutes, hours, days

    var inSeconds: Int {
        switch self {
        case .minutes: return 60
        case .hours: return 3600
        case .days: return 86400
        }
    }
}

enum TitleMode: String, CaseIterable {
    case copyOriginal = "copyOriginal"
    case rewrite = "rewrite"
}

@MainActor
class MirrorViewModel: ObservableObject {
    @Published var calendars: [EKCalendar] = []
    @Published var selectedSourceID: String = "" {
        didSet { UserDefaults.standard.set(selectedSourceID, forKey: "selectedSourceID"); updateSourceEventCount() }
    }
    @Published var selectedTargetID: String = "" {
        didSet { UserDefaults.standard.set(selectedTargetID, forKey: "selectedTargetID") }
    }

    @Published var lookbackDays: Int = 2 {
        didSet { UserDefaults.standard.set(lookbackDays, forKey: "lookbackDays"); updateSourceEventCount() }
    }
    @Published var lookaheadDays: Int = 21 {
        didSet { UserDefaults.standard.set(lookaheadDays, forKey: "lookaheadDays"); updateSourceEventCount() }
    }
    @Published var dryRun: Bool = false {
        didSet {
            UserDefaults.standard.set(dryRun, forKey: "dryRun")
            if dryRun { autoSyncEnabled = false }
        }
    }
    @Published var titleMode: TitleMode = .rewrite {
        didSet { UserDefaults.standard.set(titleMode.rawValue, forKey: "titleMode") }
    }
    @Published var title: String = "Busy" {
        didSet { UserDefaults.standard.set(title, forKey: "mirrorTitle") }
    }
    @Published var titleWasModifiedByUser: Bool = false {
        didSet { UserDefaults.standard.set(titleWasModifiedByUser, forKey: "titleWasModifiedByUser") }
    }

    @Published var sourceEventCount: Int?
    @Published var launchAtLogin: Bool = false {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    @Published var logText: String = ""
    @Published var isRunning: Bool = false
    @Published var hasAccess: Bool = false
    @Published var accessError: String?

    @Published var syncIntervalValue: Int = 15 {
        didSet { UserDefaults.standard.set(syncIntervalValue, forKey: "syncIntervalValue"); rescheduleTimer() }
    }
    @Published var syncIntervalUnit: SyncIntervalUnit = .minutes {
        didSet { UserDefaults.standard.set(syncIntervalUnit.rawValue, forKey: "syncIntervalUnit"); rescheduleTimer() }
    }
    @Published var autoSyncEnabled: Bool = false {
        didSet { UserDefaults.standard.set(autoSyncEnabled, forKey: "autoSyncEnabled"); rescheduleTimer() }
    }
    @Published var lastSyncTime: Date?
    @Published var lastSyncSummary: String?

    var nextSyncTime: Date? {
        guard autoSyncEnabled, let last = lastSyncTime else { return nil }
        return last.addingTimeInterval(TimeInterval(syncIntervalValue * syncIntervalUnit.inSeconds))
    }

    private let tagPrefix = "[MIRROR srcUID="
    private let store = EKEventStore()
    private var syncTimer: Timer?
    private var hasBeenConfigured: Bool {
        UserDefaults.standard.string(forKey: "selectedSourceID") != nil
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "syncIntervalValue") != nil {
            syncIntervalValue = defaults.integer(forKey: "syncIntervalValue")
        }
        if let unitStr = defaults.string(forKey: "syncIntervalUnit"),
           let unit = SyncIntervalUnit(rawValue: unitStr) {
            syncIntervalUnit = unit
        }
        if defaults.object(forKey: "autoSyncEnabled") != nil {
            autoSyncEnabled = defaults.bool(forKey: "autoSyncEnabled")
        }
        if let s = defaults.string(forKey: "lookbackDays"), let v = Int(s) { lookbackDays = v }
        else if defaults.object(forKey: "lookbackDays") != nil { lookbackDays = defaults.integer(forKey: "lookbackDays") }
        if let s = defaults.string(forKey: "lookaheadDays"), let v = Int(s) { lookaheadDays = v }
        else if defaults.object(forKey: "lookaheadDays") != nil { lookaheadDays = defaults.integer(forKey: "lookaheadDays") }
        if let s = defaults.string(forKey: "mirrorTitle") { title = s }
        if let modeStr = defaults.string(forKey: "titleMode"),
           let mode = TitleMode(rawValue: modeStr) {
            titleMode = mode
        }
        if defaults.object(forKey: "dryRun") != nil { dryRun = defaults.bool(forKey: "dryRun") }
        if defaults.object(forKey: "titleWasModifiedByUser") != nil { titleWasModifiedByUser = defaults.bool(forKey: "titleWasModifiedByUser") }
        if defaults.object(forKey: "launchAtLogin") != nil { launchAtLogin = defaults.bool(forKey: "launchAtLogin") }
        requestAccess()

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.syncIfOverdue()
            }
        }
    }

    private func syncIfOverdue() {
        guard autoSyncEnabled, hasAccess, !dryRun else { return }
        guard let next = nextSyncTime, Date() >= next else { return }
        appendLog("Woke from sleep — running overdue sync.")
        runMirror()
        rescheduleTimer()
    }

    private func rescheduleTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
        guard autoSyncEnabled, syncIntervalValue > 0 else { return }
        let interval = TimeInterval(syncIntervalValue * syncIntervalUnit.inSeconds)
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runMirror()
            }
        }
    }

    private func startAutoSyncIfConfigured() {
        guard hasAccess, hasBeenConfigured, autoSyncEnabled else { return }
        runMirror()
        rescheduleTimer()
    }
    
    // MARK: - Permissions
    
    private func requestAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        appendLog("Current authorization status: \(status.rawValue) (\(status))")
        
        switch status {
        case .notDetermined:
            appendLog("Status is notDetermined — requesting full access…")
            store.requestFullAccessToEvents { [weak self] granted, error in
                // Hop back to the main actor for state changes
                Task { @MainActor in
                    self?.handleAuthorizationResult(granted: granted, error: error)
                }
            }
            
        case .fullAccess:
            appendLog("Status is fullAccess — already have full read/write access.")
            hasAccess = true
            loadCalendars()
            startAutoSyncIfConfigured()
            
        case .writeOnly:
            appendLog("Status is writeOnly — cannot read calendars with write-only access.")
            hasAccess = false
            accessError = "Calendar access is write-only; enable Full Access in System Settings → Privacy & Security → Calendars."
            
        case .denied:
            appendLog("Status is denied — user has explicitly denied access.")
            hasAccess = false
            accessError = "Calendar access denied. Enable it in System Settings → Privacy & Security → Calendars."
            
        case .restricted:
            appendLog("Status is restricted — access is restricted by system policy.")
            hasAccess = false
            accessError = "Calendar access is restricted by system policy."
            
        case .authorized:
            // Deprecated but still possible; treat as full access.
            appendLog("Status is authorized — treating as fullAccess.")
            hasAccess = true
            loadCalendars()
            startAutoSyncIfConfigured()
            
        @unknown default:
            appendLog("Status is unknown (\(status)) — treating as denied.")
            hasAccess = false
            accessError = "Calendar access not available (status: \(status))."
        }
    }
    
    private func handleAuthorizationResult(granted: Bool, error: Error?) {
        if let error = error {
            appendLog("ERROR during calendar access request: \(error.localizedDescription)")
        }
        hasAccess = granted
        if granted {
            appendLog("Calendar access granted.")
            loadCalendars()
            startAutoSyncIfConfigured()
        } else {
            accessError = "Calendar access denied."
            appendLog("ERROR: Calendar access denied.")
        }
    }
    
    // MARK: - Calendars
    
    private func loadCalendars() {
        let cals = store.calendars(for: .event)
        let sorted = cals.sorted {
            $0.title.localizedCompare($1.title) == .orderedAscending
        }
        calendars = sorted

        let defaults = UserDefaults.standard
        let savedSource = defaults.string(forKey: "selectedSourceID")
        let savedTarget = defaults.string(forKey: "selectedTargetID")

        if let src = savedSource, sorted.contains(where: { $0.calendarIdentifier == src }) {
            selectedSourceID = src
        } else if let first = sorted.first {
            selectedSourceID = first.calendarIdentifier
        }

        if let tgt = savedTarget, sorted.contains(where: { $0.calendarIdentifier == tgt }) {
            selectedTargetID = tgt
        } else if sorted.count > 1 {
            selectedTargetID = sorted[1].calendarIdentifier
        } else {
            selectedTargetID = selectedSourceID
        }

        appendLog("Loaded \(sorted.count) calendars.")
        updateSourceEventCount()
    }

    private func calendar(withID id: String) -> EKCalendar? {
        calendars.first { $0.calendarIdentifier == id }
    }
    
    func updateTitleForSelectedSource() {
        // Only auto-update if the user hasn't customized the title
        guard !titleWasModifiedByUser else { return }

        if let cal = calendars.first(where: { $0.calendarIdentifier == selectedSourceID }) {
            title = "Busy - \(cal.title)"
        }
    }

    func updateSourceEventCount() {
        guard hasAccess else { return }
        guard let srcCal = calendar(withID: selectedSourceID) else {
            sourceEventCount = nil
            return
        }
        let lb = lookbackDays
        let la = lookaheadDays
        let now = Date()
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -lb, to: now),
              let end = cal.date(byAdding: .day, value: la, to: now) else {
            sourceEventCount = nil
            return
        }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: [srcCal])
        let events = store.events(matching: pred).filter { $0.availability != .free }
        sourceEventCount = events.count
    }
    
    // MARK: - Run
    
    func runMirror() {
        guard hasAccess else {
            appendLog("Cannot run: no calendar access.")
            return
        }
        
        guard let srcCal = calendar(withID: selectedSourceID) else {
            appendLog("ERROR: Source calendar not selected or not found.")
            return
        }
        guard let tgtCal = calendar(withID: selectedTargetID) else {
            appendLog("ERROR: Target calendar not selected or not found.")
            return
        }
        
        let lb = lookbackDays
        let la = lookaheadDays
        
        appendLog("Starting mirror run...")
        appendLog("Source: \(srcCal.title), Target: \(tgtCal.title)")
        appendLog("Lookback: \(lb) days, Lookahead: \(la) days, Dry run: \(dryRun ? "YES" : "NO")")
        if titleMode == .rewrite {
            appendLog("Mirror title: \(title)")
        } else {
            appendLog("Title mode: copy original")
        }
        
        // Everything below runs on the main actor (no background threads),
        // so all @Published updates are safe.
        isRunning = true
        let result = _runMirrorInternal(srcCal: srcCal,
                           tgtCal: tgtCal,
                           lookbackDays: lb,
                           lookaheadDays: la)
        isRunning = false
        lastSyncSummary = result

        if !dryRun {
            lastSyncTime = Date()
        }

        if syncTimer == nil && autoSyncEnabled {
            rescheduleTimer()
        }
    }
    
    // MARK: - Core mirror logic
    
    private func _runMirrorInternal(srcCal: EKCalendar,
                                    tgtCal: EKCalendar,
                                    lookbackDays: Int,
                                    lookaheadDays: Int) -> String {
        let now = Date()
        let cal = Calendar.current
        
        guard let start = cal.date(byAdding: .day, value: -lookbackDays, to: now),
              let end   = cal.date(byAdding: .day, value:  lookaheadDays, to: now) else {
            appendLog("ERROR: Failed to compute date range.")
            return "Error"
        }
        
        let srcPred = store.predicateForEvents(withStart: start, end: end, calendars: [srcCal])
        let tgtPred = store.predicateForEvents(withStart: start, end: end, calendars: [tgtCal])
        
        var srcEvents = store.events(matching: srcPred)
        srcEvents.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        var tgtEvents = store.events(matching: tgtPred)
        
        func mirrorKey(for e: EKEvent) -> String {
            let calID = e.calendarItemIdentifier
            if !calID.isEmpty { return "\(tagPrefix)\(calID)]" }
            
            guard let s = e.startDate, let ee = e.endDate else {
                return "\(tagPrefix)NOID:\(UUID().uuidString)]"
            }
            let key = "S\(Int(s.timeIntervalSince1970))_E\(Int(ee.timeIntervalSince1970))"
            return "\(tagPrefix)\(key)]"
        }
        
        var srcKeys: Set<String> = []
        var created = 0, updated = 0, deleted = 0
        
        for e in srcEvents {
            // Skip free events
            if e.availability == .free { continue }
            guard let s = e.startDate else { continue }

            let eEnd0 = e.endDate ?? s.addingTimeInterval(15 * 60)
            let eEnd  = (eEnd0 <= s) ? s.addingTimeInterval(15 * 60) : eEnd0
            let mirrorTitle = titleMode == .copyOriginal ? (e.title ?? "Busy") : title

            let k = mirrorKey(for: e)
            srcKeys.insert(k)

            // Find existing mirror
            var mirror: EKEvent? = nil
            for m in tgtEvents {
                if let notes = m.notes, notes.contains(k) {
                    mirror = m
                    break
                }
            }

            if let m = mirror {
                var needUpdate = false
                if m.isAllDay != e.isAllDay { needUpdate = true }
                if m.startDate != s || m.endDate != eEnd { needUpdate = true }
                if m.title != mirrorTitle { needUpdate = true }

                if needUpdate {
                    if !dryRun {
                        m.isAllDay = e.isAllDay
                        m.startDate = s
                        m.endDate = eEnd
                        m.title = mirrorTitle
                        m.availability = .busy
                        m.alarms = []
                        do {
                            try store.save(m, span: .thisEvent, commit: false)
                        } catch {
                            appendLog("WARN: Failed to update mirror: \(error)")
                        }
                    }
                    updated += 1
                    appendLog("Updated mirror for \(e.title ?? "(no title)") at \(s)")
                } else {
                    appendLog("No changes for \(e.title ?? "(no title)") at \(s)")
                }
            } else {
                if !dryRun {
                    let m = EKEvent(eventStore: store)
                    m.calendar = tgtCal
                    m.title = mirrorTitle
                    m.startDate = s
                    m.endDate = eEnd
                    m.isAllDay = e.isAllDay
                    m.availability = .busy
                    m.notes = k
                    m.alarms = []
                    do {
                        try store.save(m, span: .thisEvent, commit: false)
                        tgtEvents.append(m)
                    } catch {
                        appendLog("WARN: Failed to create mirror: \(error)")
                    }
                }
                created += 1
                appendLog("Created mirror for \(e.title ?? "(no title)") at \(s)")
            }
        }
        
        // Sweep: remove reminders from all mirrors
        for m in tgtEvents {
            if let notes = m.notes, notes.contains(tagPrefix) {
                if (m.alarms?.isEmpty == false) && !dryRun {
                    m.alarms = []
                    do {
                        try store.save(m, span: .thisEvent, commit: false)
                    } catch {
                        appendLog("WARN: Failed to clear alarms: \(error)")
                    }
                }
            }
        }
        
        // Delete stale mirrors
        for m in tgtEvents {
            guard let notes = m.notes, notes.contains(tagPrefix) else { continue }
            var keep = false
            for k in srcKeys {
                if notes.contains(k) {
                    keep = true
                    break
                }
            }
            if !keep {
                if !dryRun {
                    do {
                        try store.remove(m, span: .thisEvent, commit: false)
                    } catch {
                        appendLog("WARN: Failed to delete stale mirror: \(error)")
                    }
                }
                deleted += 1
                appendLog("Deleted stale mirror: \(m.title ?? "(no title)")")
            }
        }
        
        if !dryRun {
            do {
                try store.commit()
            } catch {
                appendLog("ERROR: Commit failed: \(error)")
                return "Error"
            }
        }

        let summary = "Created: \(created), Updated: \(updated), Deleted: \(deleted)"
        appendLog("Run complete. \(summary)")
        return summary
    }
    
    // MARK: - Logging
    
    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let ts = formatter.string(from: Date())
        logText.append("[\(ts)] \(message)\n")
    }
}
