//
//  AppLinksView.swift
//  MenuScores
//
//  Created by Daniyal Master on 2025-08-02.
//

import SwiftUI

struct AppLinksView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        VStack(spacing: 8) {
            Image("TahoeIcon")
                .resizable()
                .frame(width: 67, height: 67)
                .cornerRadius(4)
                .padding(.top, 10)
                .padding(.bottom, 5)

            Text("Matcha ")
                .font(.title2)
                .bold()
                .foregroundColor(.primary)
                +
                Text(version)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Form {
                Section {
                    HStack {
                        Text("Version")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(version)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    ForEach(
                        [
                            ("Matcha Help", "https://github.com/suhasvemuri/Matcha"),
                            ("Feedback", "https://github.com/suhasvemuri/Matcha/issues/new"),
                            ("Changelog", "https://github.com/suhasvemuri/Matcha/releases"),
                            ("License", "https://github.com/suhasvemuri/Matcha/blob/main/License"),

                        ],
                        id: \.0
                    ) { item in
                        Button(action: {
                            if let url = URL(string: item.1) {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack {
                                Text(item.0)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 650)
            .padding(.top, 7)

            Divider()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .padding(.top, 7)
        .frame(width: 350, height: 425)
    }
}
