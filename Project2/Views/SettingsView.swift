//
//  SettingsView.swift
//  Project2
//
//  Created by Alex on 1.09.25.
//
//  Spec 07 "Layout": General (main currency, appearance), iCloud, About.
//  Spec 12: "Support the Developer" between iCloud and About, only with a Tip Jar.
//

import SwiftUI

/// Presented as a sheet from Home's toolbar (spec 08: no tab bar).
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    /// `nil` while the Tip Jar flag is off: no section at all (TJ-01).
    @Environment(TipJar.self) private var tipJar: TipJar?
    @Environment(\.dismiss) private var dismiss
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

                if let tipJar {
                    TipJarSection(tipJar: tipJar)
                }

                Section("About") {
                    LabeledContent("Version") {
                        Text(verbatim: AppVersion.text(from: Bundle.main.infoDictionary ?? [:]))
                    }
                    .accessibilityIdentifier("settings.version")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        dismiss()
                    }
                    .accessibilityIdentifier("settings.doneButton")
                }
            }
        }
    }
}

/// Spec 12 § Settings: one row to the Tip Jar; after a tip it says thank you (TJ-18).
private struct TipJarSection: View {
    let tipJar: TipJar

    var body: some View {
        Section {
            NavigationLink {
                TipJarView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Leave a Tip")
                        if tipJar.hasTipped {
                            Text("Thank you for your support!")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: tipJar.hasTipped ? "heart.fill" : "heart")
                        .foregroundStyle(.pink)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("settings.tipJar")
        } header: {
            Text("Support the Developer")
        } footer: {
            Text("Tips don't unlock anything — the app stays free.")
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
