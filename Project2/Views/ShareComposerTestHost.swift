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
    /// Safari: og:title "KIVIK 3-seat sofa - IKEA", an og:image (stub picture) and a
    /// JSON-LD price of EUR 449.00 (SE-02, SE-02b, SE-07, B3).
    case safari
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
        case .safari:
            ShareInput.from(urls: [URL(string: "https://www.ikea.com/us/en/p/kivik-sofa-s39405")!],
                            texts: ["KIVIK 3-seat sofa, Tresund light beige - IKEA"],
                            page: Self.safariPage)
        case .bad, .unavailable:
            ShareInput.from(urls: [URL(string: "mailto:shop@example.com")!], texts: [])
        }
    }

    /// What `SharePreprocessing.js` would collect on an IKEA product page.
    private static let safariPage = SharePage(results: [
        SharePage.Key.url: "https://www.ikea.com/us/en/p/kivik-sofa-s39405",
        SharePage.Key.title: "KIVIK 3-seat sofa, Tresund light beige - IKEA",
        SharePage.Key.ogTitle: "KIVIK 3-seat sofa - IKEA",
        SharePage.Key.ogImage: "https://www.ikea.com/images/kivik.jpg",
        SharePage.Key.jsonLD: [#"{"@context":"https://schema.org","@type":"Product","name":"KIVIK","offers":{"@type":"Offer","price":"449.00","priceCurrency":"EUR"}}"#],
    ])

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
            titleTimeout: .seconds(30),
            imageLoader: StubShareImageLoader()))
    }
}
