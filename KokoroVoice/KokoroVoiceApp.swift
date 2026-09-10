// KokoroVoice/KokoroVoiceApp.swift
// KokoroVoice
//
// Main application entry point for the Kokoro Voice host app.

import SwiftUI

@main
struct KokoroVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 700)
        .commands {
            // Custom menu commands
            CommandGroup(replacing: .help) {
                Button("Kokoro Voice Help") {
                    if let url = URL(string: "https://github.com/mlalma/kokoro-ios") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("?", modifiers: .command)
            }

            CommandGroup(after: .appSettings) {
                Button("Open Accessibility Settings...") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            }
        }

        #if os(macOS)
        Settings {
            SettingsView(voiceManager: VoiceManager())
        }
        #endif
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // PluginKit owns the registered speech-provider extension. The host is
        // only a manager and preview surface, so keeping it alive would retain
        // a second copy of the neural model without helping system speech.
        true
    }
}

// MARK: - App Icon Badge (for status indication)

extension NSApplication {
    func updateDockBadge(enabledVoiceCount: Int) {
        if enabledVoiceCount > 0 {
            dockTile.badgeLabel = "\(enabledVoiceCount)"
        } else {
            dockTile.badgeLabel = nil
        }
    }
}
