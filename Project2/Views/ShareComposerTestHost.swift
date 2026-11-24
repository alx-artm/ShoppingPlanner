//
//  ShareComposerTestHost.swift
//  Project2
//
//  `-UITests -UITestsShareComposer <scenario>`: the Share Extension's screen in a sheet of the
//  app, on the app's in-memory store (spec 06 B.5). XCUITest can't drive a real share sheet
//  reliably on CI, so the UI tests check this same `ShareRootView`; the extension's own glue
//  (`ShareViewController`) is checked by hand.
//

import SwiftUI

/// What the composer was "shared" in a UI test. Titles come from `StubLinkMetadataFetcher`
/// with `-UITestsLinkPreview stub`.
enum ShareComposerScenario: String {
    /// A link and the sharing app's text "KIVIK 3-seat sofa - Example"; the page title fails.
    case appText
    /// Only `https://slow.example.com/x`: the host first, the title after 2 s (SE-02a).
    case urlOnly
    /// Only `https://veryslow.example.com/x`: the title after 8 s, time to type first (SE-02a).
    case urlOnlyEdit
    /// `mailto:`: "This link can't be added".
    case bad
    /// The store can't be opened: "isn't available right now".
    case unavailable

    var input: ShareInput {
        switch self {
        case .appText:
            ShareInput.from(urls: [URL(string: "https://fail.example.com/kivik-sofa")!],
                            texts: ["KIVIK 3-seat sofa - Example"])
        case .urlOnly:
            ShareInput.from(urls: [URL(string: "https://slow.example.com/x")!], texts: [])
        case .urlOnlyEdit:
            ShareInput.from(urls: [URL(string: "https://veryslow.example.com/x")!], texts: [])
        case .bad, .unavailable:
            ShareInput.from(urls: [URL(string: "mailto:shop@example.com")!], texts: [])
        }
    }

    /// Volatile "last used" list and group: every launch starts without them.
    @MainActor static let defaults: UserDefaults = {
        let suiteName = "ShareDefaults.uiTests"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }()
}

/// Shows the composer once at launch when a UI test asks for it.
struct ShareComposerTestHost: ViewModifier {
    @Environment(PlannerStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var screen: ShareScreen?
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard screen == nil, let name = LaunchConfiguration.shareComposerScenario,
                      let scenario = ShareComposerScenario(rawValue: name) else { return }
                screen = makeScreen(scenario)
                isPresented = true
            }
            .sheet(isPresented: $isPresented) {
                if let screen {
                    ShareRootView(screen: screen, onSave: { isPresented = false },
                                  onCancel: { isPresented = false })
                }
            }
    }

    private func makeScreen(_ scenario: ShareComposerScenario) -> ShareScreen {
        if scenario == .unavailable { return .unavailable }
        guard case .link(let payload) = scenario.input else { return .unsupported }
        return .compose(ShareComposerModel(
            payload: payload, store: store, shareDefaults: ShareDefaults(defaults: ShareComposerScenario.defaults),
            mainCurrencyCode: settings.mainCurrencyCode,
            titleFetcher: LinkFetcherKind.current.makeFetcher(),
            // Longer than the stub's 8 s `veryslow` host, so SE-02a can be checked unhurried;
            // the 5-second rule itself is a unit test (`ShareComposerTests.titleTimeout`).
            titleTimeout: .seconds(30)))
    }
}
