import SwiftUI
import EventKit

struct ContentView: View {
    @ObservedObject var viewModel: MirrorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CalendarMirror")
                .font(.title)
                .padding(.bottom, 4)

            if let err = viewModel.accessError {
                Text(err)
                    .foregroundColor(.red)
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("Source Calendar")
                    Picker("", selection: $viewModel.selectedSourceID) {
                        ForEach(viewModel.calendars, id: \.calendarIdentifier) { cal in
                            Text(cal.title).tag(cal.calendarIdentifier)
                        }
                    }
                    .onChange(of: viewModel.selectedSourceID) {
                        viewModel.updateTitleForSelectedSource()
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                VStack(alignment: .leading) {
                    Text("Target Calendar")
                    Picker("", selection: $viewModel.selectedTargetID) {
                        ForEach(viewModel.calendars, id: \.calendarIdentifier) { cal in
                            Text(cal.title).tag(cal.calendarIdentifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("Lookback (days)")
                    TextField("", text: $viewModel.lookbackDays)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading) {
                    Text("Lookahead (days)")
                    TextField("", text: $viewModel.lookaheadDays)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Dry run (no changes)", isOn: $viewModel.dryRun)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading) {
                Text("Mirror Title")
                TextField("Busy", text: $viewModel.title, onEditingChanged: { isEditing in
                    if isEditing {
                        viewModel.titleWasModifiedByUser = true
                    }
                })
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                Toggle("Auto-sync", isOn: $viewModel.autoSyncEnabled)
                    .toggleStyle(.switch)

                VStack(alignment: .leading) {
                    Text("Interval (minutes)")
                    Stepper(value: $viewModel.syncIntervalMinutes, in: 1...120) {
                        Text("\(viewModel.syncIntervalMinutes)")
                            .frame(width: 30)
                    }
                }

                if let lastSync = viewModel.lastSyncTime {
                    Text("Last sync: \(lastSync.formatted(date: .omitted, time: .standard))")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }

            HStack {
                Button(action: {
                    viewModel.runMirror()
                }) {
                    HStack {
                        if viewModel.isRunning {
                            ProgressView()
                        }
                        Text(viewModel.isRunning ? "Running..." : "Sync Now")
                    }
                }
                .disabled(viewModel.isRunning || !viewModel.hasAccess)
            }
            .padding(.vertical, 4)

            Text("Log")
                .font(.headline)
                .padding(.top, 4)

            LogTextView(text: $viewModel.logText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 500)
    }
}
