//
//  LeagueSettings.swift
//  MenuScores
//
//  Created by Daniyal Master on 2025-07-10.
//

import SwiftUI

struct LeagueSettingsView: View {
    // Toggled League Settings

    @AppStorage("enableNHL") private var enableNHL = true
    @AppStorage("enableHNCAAM") private var enableHNCAAM = false
    @AppStorage("enableHNCAAF") private var enableHNCAAF = false

    @AppStorage("enableNBA") private var enableNBA = true
    @AppStorage("enableWNBA") private var enableWNBA = false
    @AppStorage("enableNCAAM") private var enableNCAAM = false
    @AppStorage("enableNCAAF") private var enableNCAAF = false

    @AppStorage("enableNFL") private var enableNFL = true
    @AppStorage("enableFNCAA") private var enableFNCAA = false

    @AppStorage("enableMLB") private var enableMLB = true
    @AppStorage("enableBNCAA") private var enableBNCAA = false
    @AppStorage("enableSNCAA") private var enableSNCAA = false

    @AppStorage("enableF1") private var enableF1 = true
    @AppStorage("enableNC") private var enableNC = false
    @AppStorage("enableNCS") private var enableNCS = false
    @AppStorage("enableNCT") private var enableNCT = false
    @AppStorage("enableIRL") private var enableIRL = false

    @AppStorage("enablePGA") private var enablePGA = true
    @AppStorage("enableLPGA") private var enableLPGA = false

    @AppStorage("enableMLS") private var enableMLS = true
    @AppStorage("enableNWSL") private var enableNWSL = false
    @AppStorage("enableUEFA") private var enableUEFA = false
    @AppStorage("enableEUEFA") private var enableEUEFA = false
    @AppStorage("enableWUEFA") private var enableWUEFA = false
    @AppStorage("enableMEX") private var enableMEX = false
    @AppStorage("enableFRA") private var enableFRA = false
    @AppStorage("enableNED") private var enableNED = false
    @AppStorage("enablePOR") private var enablePOR = false
    @AppStorage("enableEPL") private var enableEPL = false
    @AppStorage("enableWEPL") private var enableWEPL = false
    @AppStorage("enableESP") private var enableESP = false
    @AppStorage("enableGER") private var enableGER = false
    @AppStorage("enableITA") private var enableITA = false

    @AppStorage("enableFFWC") private var enableFFWC = false
    @AppStorage("enableFFWWC") private var enableFFWWC = false
    @AppStorage("enableFFWCQUEFA") private var enableFFWCQUEFA = false
    @AppStorage("enableCONCACAF") private var enableCONCACAF = false
    @AppStorage("enableCONMEBOL") private var enableCONMEBOL = false
    @AppStorage("enableCAF") private var enableCAF = false
    @AppStorage("enableAFC") private var enableAFC = false
    @AppStorage("enableOFC") private var enableOFC = false
    @AppStorage("enableCricket") private var enableCricket = true

    @AppStorage("enableATP") private var enableATP = true
    @AppStorage("enableWTA") private var enableWTA = false

    @AppStorage("enableUFC") private var enableUFC = true

    @AppStorage("enableNLL") private var enableNLL = true
    @AppStorage("enablePLL") private var enablePLL = false
    @AppStorage("enableLNCAAM") private var enableLNCAAM = false
    @AppStorage("enableLNCAAF") private var enableLNCAAF = false

    @AppStorage("enableVNCAAM") private var enableVNCAAM = true
    @AppStorage("enableVNCAAF") private var enableVNCAAF = false

    @AppStorage("enableOMIHC") private var enableOMIHC = true
    @AppStorage("enableOWIHC") private var enableOWIHC = false

    // League Settings View

    var body: some View {
        VStack(spacing: 4) {
            Text("Leagues")
                .font(.title2)
                .bold()

            Form {
                Section("Core Sports") {
                    Toggle(isOn: $enableCricket) {
                        Label("Cricket (ICC + IPL)", systemImage: "sportscourt")
                    }

                    Toggle(isOn: $enableMLS) { Label("MLS", systemImage: "soccerball") }
                    Toggle(isOn: $enableUEFA) { Label("Champions League", systemImage: "soccerball") }
                    Toggle(isOn: $enableEPL) { Label("Premier League", systemImage: "soccerball") }
                    Toggle(isOn: $enableESP) { Label("La Liga", systemImage: "soccerball") }
                    Toggle(isOn: $enableGER) { Label("Bundesliga", systemImage: "soccerball") }
                    Toggle(isOn: $enableITA) { Label("Serie A", systemImage: "soccerball") }
                }

                Section("Soccer International") {
                    Toggle(isOn: $enableFFWC) { Label("FIFA World Cup", systemImage: "trophy") }
                    Toggle(isOn: $enableFFWCQUEFA) { Label("UEFA Qualifiers", systemImage: "trophy") }
                    Toggle(isOn: $enableCONMEBOL) { Label("CONMEBOL Qualifiers", systemImage: "trophy") }
                    Toggle(isOn: $enableCONCACAF) { Label("CONCACAF Qualifiers", systemImage: "trophy") }
                    Toggle(isOn: $enableCAF) { Label("CAF Qualifiers", systemImage: "trophy") }
                    Toggle(isOn: $enableAFC) { Label("AFC Qualifiers", systemImage: "trophy") }
                    Toggle(isOn: $enableOFC) { Label("OFC Qualifiers", systemImage: "trophy") }
                }

                Section("Optional Add-ons") {
                    Toggle(isOn: $enableNBA) { Label("NBA", systemImage: "basketball") }
                    Toggle(isOn: $enableNFL) { Label("NFL", systemImage: "football") }
                    Toggle(isOn: $enableF1) { Label("F1", systemImage: "flag.checkered") }
                }

                Section {
                    Button("Apply Core Preset") {
                        applyCorePreset()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Disable Optional Add-ons") {
                        enableNBA = false
                        enableNFL = false
                        enableF1 = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func applyCorePreset() {
        // Disable non-priority sports/leagues.
        enableNHL = false
        enableHNCAAM = false
        enableHNCAAF = false
        enableWNBA = false
        enableNCAAM = false
        enableNCAAF = false
        enableFNCAA = false
        enableMLB = false
        enableBNCAA = false
        enableSNCAA = false
        enableNC = false
        enableNCS = false
        enableNCT = false
        enableIRL = false
        enablePGA = false
        enableLPGA = false
        enableNWSL = false
        enableEUEFA = false
        enableWUEFA = false
        enableMEX = false
        enableFRA = false
        enableNED = false
        enablePOR = false
        enableWEPL = false
        enableFFWWC = false
        enableATP = false
        enableWTA = false
        enableUFC = false
        enableNLL = false
        enablePLL = false
        enableLNCAAM = false
        enableLNCAAF = false
        enableVNCAAM = false
        enableVNCAAF = false
        enableOMIHC = false
        enableOWIHC = false
    }
}
