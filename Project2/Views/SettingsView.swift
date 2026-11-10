//
//  SettingsView.swift
//  Project2
//
//  Created by Alex on 1.09.25.
//
//  Spec 07 "Layout": General (main currency, appearance), iCloud, About.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.locale) private var locale
    @AppStorage("selectedTheme") private var selectedTheme: AppTheme = .system

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CurrencyPickerView(selection: $settings.mainCurrencyCode)
                    } label: {
                        LabeledContent("Main Currency") {
                            Text(verbatim: CurrencyCatalog.rowTitle(of: settings.mainCurrencyCode, locale: locale))
                        }
                    }
                    .accessibilityIdentifier("settings.mainCurrency")
                } header: {
                    Text("General")
                } footer: {
                    // SC-07
                    Text("Used for new lists. Existing lists keep their currency.")
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $selectedTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("settings.appearancePicker")
                }

                Section {
                    // Sync arrives in M6 (SC-10); until then data is local only.
                    LabeledContent("iCloud Sync", value: String(localized: "Off"))
                        .accessibilityIdentifier("settings.icloudStatus")
                } header: {
                    Text(verbatim: "iCloud")
                } footer: {
                    Text("Data stays on this device.")
                }

                Section("About") {
                    LabeledContent("Version") {
                        Text(verbatim: AppVersion.text(from: Bundle.main.infoDictionary ?? [:]))
                    }
                    .accessibilityIdentifier("settings.version")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

/// "1.0 (7)": marketing version and build number from Info.plist.
enum AppVersion {
    static func text(from info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .sampleDataEnvironment()
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// Localized title (a plain `String` would be shown verbatim, untranslated).
    var title: LocalizedStringResource {
        switch self {
        case .system: "Match device"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
