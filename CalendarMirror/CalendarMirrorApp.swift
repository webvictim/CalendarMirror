import SwiftUI
import EventKit
import Combine

@main
struct CalendarMirrorApp: App {
    @StateObject private var viewModel = MirrorViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            Label("CalendarMirror", image: "MenuBarIcon")
        }

        Window("CalendarMirror", id: "main") {
            ContentView(viewModel: viewModel)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObservers: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Close any auto-opened windows on launch so we start as menu-bar-only
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title == "CalendarMirror" {
                window.close()
            }
        }

        windowObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow,
                      window.title == "CalendarMirror" else { return }
                NSApp.setActivationPolicy(.regular)
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        )
        windowObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: nil, queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow,
                      window.title == "CalendarMirror" else { return }
                DispatchQueue.main.async {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        )
    }
}

struct MenuBarView: View {
    @ObservedObject var viewModel: MirrorViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let lastSync = viewModel.lastSyncTime {
            Text("Last sync: \(lastSync.formatted(date: .omitted, time: .shortened))")
            if let summary = viewModel.lastSyncSummary {
                Text(summary)
            }
        } else {
            Text("Not yet synced")
        }

        Divider()

        Button(viewModel.dryRun ? "Sync Now (Dry run: on)" : "Sync Now") {
            viewModel.runMirror()
        }
        .disabled(viewModel.isRunning || !viewModel.hasAccess || viewModel.dryRun)

        Button("Open Window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
