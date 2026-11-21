//
//  LinkOpener.swift
//  Project2
//
//  The one way views open an item's link (spec 06 A.1 p.5, A.5, D4):
//  - `.inApp` — Safari inside the app (`SFSafariViewController`, see `InAppBrowser.swift`):
//    a tap on the link card. The screen on top provides it with `.inAppBrowser()`; without
//    one the link opens like `.external`, never silently nothing;
//  - `.external` — plain `openURL(url)`: the shop's app for a universal link, else Safari
//    ("Open in Safari").
//  With `-UITests -UITestsRecordOpenedLinks` nothing is opened: the link is written to
//  `debug.lastOpenedLink`, so a UI test checks what would open without leaving the app.
//

import Observation
import SwiftUI

struct LinkOpener: Sendable {
    enum Destination: String, Sendable {
        case inApp
        case external
    }

    /// Set only in UI tests: links are recorded instead of opened.
    let recorder: OpenedLinkRecorder?
    /// Shows the in-app browser; set by `.inAppBrowser()` for the views under it.
    private(set) var presentInApp: (@MainActor @Sendable (URL) -> Void)?

    init(recorder: OpenedLinkRecorder? = nil) {
        self.recorder = recorder
    }

    /// The same opener, showing `.inApp` links with `present`.
    func presentingInApp(_ present: @escaping @MainActor @Sendable (URL) -> Void) -> LinkOpener {
        var opener = self
        opener.presentInApp = present
        return opener
    }

    /// `openURL` is the view's `@Environment(\.openURL)`: it opens in the view's own scene.
    @MainActor
    func open(_ url: URL, _ destination: Destination, using openURL: OpenURLAction) {
        if let recorder {
            recorder.record(url, destination)
            return
        }
        // `openURL(url, prefersInApp: true)` (iOS 26) opened nothing on iOS 26.5 (spec 06
        // A.1 p.5 check in PR 3), so `.inApp` uses our own Safari view controller.
        if destination == .inApp, let presentInApp {
            presentInApp(url)
        } else {
            openURL(url)
        }
    }

    /// The opener of this launch: recording with `-UITests -UITestsRecordOpenedLinks`.
    @MainActor
    static func forLaunch(arguments: [String]) -> LinkOpener {
        LaunchConfiguration.recordsOpenedLinks(arguments: arguments)
            ? LinkOpener(recorder: OpenedLinkRecorder())
            : LinkOpener()
    }
}

/// What a UI test reads instead of a browser opening (spec 06 A.5).
@MainActor
@Observable
final class OpenedLinkRecorder {
    /// What a UI test sees before any link was opened (an empty text has no accessibility element).
    nonisolated static let nothingOpened = "none"

    /// "inApp https://…" or "external https://…"; `nothingOpened` until a link is opened.
    private(set) var lastOpenedLink = OpenedLinkRecorder.nothingOpened

    func record(_ url: URL, _ destination: LinkOpener.Destination) {
        lastOpenedLink = "\(destination.rawValue) \(url.absoluteString)"
    }
}

extension EnvironmentValues {
    /// Opens links for real unless the app runs with `-UITestsRecordOpenedLinks`.
    @Entry var linkOpener = LinkOpener()
}

/// The recorded link as a text a UI test can read (`debug.lastOpenedLink`). Only exists
/// while recording; tiny and almost transparent, as no user ever runs in that mode.
private struct OpenedLinkProbe: ViewModifier {
    @Environment(\.linkOpener) private var linkOpener

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomLeading) {
            if let recorder = linkOpener.recorder {
                Text(verbatim: recorder.lastOpenedLink)
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("debug.lastOpenedLink")
            }
        }
    }
}

extension View {
    /// Adds `debug.lastOpenedLink` while links are recorded (UI tests); no-op otherwise.
    func openedLinkProbe() -> some View {
        modifier(OpenedLinkProbe())
    }
}
