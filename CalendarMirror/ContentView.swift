import SwiftUI
import EventKit

struct ContentView: View {
    @ObservedObject var viewModel: MirrorViewModel

    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image("AppIconImage")
                    .resizable()
                    .frame(width: 48, height: 48)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CalendarMirror")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("v0.1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let lastSync = viewModel.lastSyncTime {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Last sync")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lastSync.formatted(date: .omitted, time: .standard))
                            .font(.system(.caption, design: .monospaced))
                        if let nextSync = viewModel.nextSyncTime {
                            Text("Next sync")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                            Text(nextSync.formatted(
                                Calendar.current.isDate(nextSync, inSameDayAs: Date())
                                    ? .dateTime.hour().minute().second()
                                    : .dateTime.month().day().hour().minute()
                            ))
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            .padding(16)

            Divider()

            // Main content
            Form {
                Section("Calendars") {
                    Picker("Source", selection: $viewModel.selectedSourceID) {
                        ForEach(viewModel.calendars, id: \.calendarIdentifier) { cal in
                            Text(cal.title).tag(cal.calendarIdentifier)
                        }
                    }
                    .onChange(of: viewModel.selectedSourceID) {
                        viewModel.updateTitleForSelectedSource()
                    }

                    Picker("Target", selection: $viewModel.selectedTargetID) {
                        ForEach(viewModel.calendars, id: \.calendarIdentifier) { cal in
                            Text(cal.title).tag(cal.calendarIdentifier)
                        }
                    }
                }

                Section("Mirror Settings") {
                    Picker("Event title", selection: $viewModel.titleMode) {
                        Text("Copy original title").tag(TitleMode.copyOriginal)
                        Text("Rewrite title").tag(TitleMode.rewrite)
                    }

                    if viewModel.titleMode == .rewrite {
                        TextField("Mirror Title", text: $viewModel.title, onEditingChanged: { isEditing in
                            if isEditing {
                                viewModel.titleWasModifiedByUser = true
                            }
                        })
                    }

                    HStack {
                        Text("Lookback (days)")
                        Spacer()
                        TextField("", value: $viewModel.lookbackDays, format: .number)
                            .frame(width: 50)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $viewModel.lookbackDays, in: 0...90)
                        .labelsHidden()
                    }

                    HStack {
                        Text("Lookahead (days)")
                        Spacer()
                        TextField("", value: $viewModel.lookaheadDays, format: .number)
                            .frame(width: 50)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $viewModel.lookaheadDays, in: 1...365)
                        .labelsHidden()
                    }

                    if let count = viewModel.sourceEventCount {
                        Text("\(count) \(count == 1 ? "event" : "events") matching in source calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Toggle("Dry run (no changes)", isOn: $viewModel.dryRun)
                }

                Section("Sync Schedule") {
                    if viewModel.dryRun {
                        HStack {
                            Text("Auto-sync")
                            Spacer()
                            Text("Disabled (dry run is on)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Toggle("Auto-sync", isOn: $viewModel.autoSyncEnabled)

                        if viewModel.autoSyncEnabled {
                            HStack {
                                Text("Every")
                                TextField("", value: $viewModel.syncIntervalValue, format: .number)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.trailing)
                                Picker("", selection: $viewModel.syncIntervalUnit) {
                                    Text("minutes").tag(SyncIntervalUnit.minutes)
                                    Text("hours").tag(SyncIntervalUnit.hours)
                                    Text("days").tag(SyncIntervalUnit.days)
                                }
                                .labelsHidden()
                                .frame(width: 100)
                            }
                        }
                    }

                    HStack {
                        Button(action: { viewModel.runMirror() }) {
                            HStack(spacing: 6) {
                                if viewModel.isRunning {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(viewModel.isRunning ? "Syncing..." : (viewModel.autoSyncEnabled ? "Start" : "Sync Now"))
                            }
                        }
                        .disabled(viewModel.isRunning || !viewModel.hasAccess)
                        .controlSize(.large)

                        if let summary = viewModel.lastSyncSummary {
                            Text(summary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
                }
            }
            .formStyle(.grouped)

            if let err = viewModel.accessError {
                Text(err)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            Divider()

            // Log
            DisclosureGroup(isExpanded: $logExpanded) {
                LogTextView(text: $viewModel.logText)
                    .frame(height: geometry.size.height * 0.2)
            } label: {
                Text("Log")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 400)
    }

    @State private var logExpanded: Bool = true
}
