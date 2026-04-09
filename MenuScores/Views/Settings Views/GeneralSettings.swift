//
//  GeneralSettings.swift
//  MenuScores
//
//  Created by Daniyal Master on 2025-07-10.
//

import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("showInDock") private var showInDock = false
    @EnvironmentObject private var updaterController: MatchaUpdaterController

    func updateActivationPolicy() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("General")
                .font(.title2)
                .bold()

            Form {
                Section {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.secondary)
                        LaunchAtLogin.Toggle()
                    }

                    HStack {
                        Toggle(isOn: $showInDock) {
                            HStack {
                                Image(systemName: "dock.rectangle")
                                    .foregroundColor(.secondary)
                                Text("Show in Dock")
                            }
                        }
                        .onChange(of: showInDock) { _, newValue in
                            UserDefaults.standard.set(
                                newValue, forKey: "showInDock"
                            )

                            if newValue {
                                NSApp.setActivationPolicy(.regular)
                            } else {
                                NSApp.setActivationPolicy(.accessory)
                            }
                        }
                    }
                } header: {
                    Text("App")
                }

                Section {
                    Button {
                        updaterController.checkForUpdates()
                    } label: {
                        Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!updaterController.canCheckForUpdates)

                    Toggle(
                        isOn: Binding(
                            get: { updaterController.automaticallyChecksForUpdates },
                            set: { updaterController.setAutomaticallyChecksForUpdates($0) }
                        )
                    ) {
                        Label("Automatically check for updates", systemImage: "clock.badge.checkmark")
                    }

                    Toggle(
                        isOn: Binding(
                            get: { updaterController.automaticallyDownloadsUpdates },
                            set: { updaterController.setAutomaticallyDownloadsUpdates($0) }
                        )
                    ) {
                        Label("Automatically download updates", systemImage: "arrow.down.circle")
                    }
                    .disabled(!updaterController.automaticallyChecksForUpdates)

                    LabeledContent("Update feed") {
                        Text(updaterController.feedURLText)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Updates")
                }
            }
            .formStyle(.grouped)
        }
    }
}
