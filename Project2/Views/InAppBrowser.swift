//
//  InAppBrowser.swift
//  Project2
//
//  The in-app browser of `LinkOpener.inApp` (spec 06 A.1 p.5, fallback): Safari inside
//  the app (`SFSafariViewController`). The iOS 26 system way, `openURL(url, prefersInApp:
//  true)`, was checked in PR 3 and opened nothing at all on the iOS 26.5 simulator.
//
//  `SFSafariViewController` is presented by UIKit, modally, as Apple intends, not wrapped in
//  a SwiftUI `fullScreenCover`: it dismisses itself on ✕, and inside a cover that dismissal
//  plus the cover's own reset closed the item sheet under it as well.
//  It is presented from a hidden anchor controller inside the screen on top (a sheet can't
//  be covered from the screen under it), so each such screen adds `.inAppBrowser()` itself.
//

import SafariServices
import SwiftUI
import UIKit

private struct InAppBrowserHost: ViewModifier {
    @Environment(\.linkOpener) private var linkOpener
    /// Same object for the life of the view: it only holds the anchor controller.
    @State private var anchor = BrowserAnchor()

    func body(content: Content) -> some View {
        content
            .environment(\.linkOpener, linkOpener.presentingInApp { [anchor] url in
                anchor.present(url)
            })
            .background {
                BrowserAnchorView(anchor: anchor)
                    .accessibilityHidden(true)
            }
    }
}

/// Presents Safari from a view controller that lives in this screen's hierarchy.
@MainActor
private final class BrowserAnchor {
    weak var controller: UIViewController?

    func present(_ url: URL) {
        // Already showing something (a second tap while the browser slides in): ignore.
        guard let controller, controller.presentedViewController == nil else { return }
        let safari = SFSafariViewController(url: url)
        safari.dismissButtonStyle = .close
        controller.present(safari, animated: true)
    }
}

/// An empty controller in the hierarchy, so UIKit knows where to present from.
private struct BrowserAnchorView: UIViewControllerRepresentable {
    let anchor: BrowserAnchor

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        anchor.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        anchor.controller = controller
    }
}

extension View {
    /// Lets `LinkOpener.inApp` show links in Safari inside the app, over this view.
    func inAppBrowser() -> some View {
        modifier(InAppBrowserHost())
    }
}
