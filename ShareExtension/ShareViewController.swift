//
//  ShareViewController.swift
//  ShareExtension
//
//  The Share Extension's entry point (spec 06 Part B, B.4 p.9): reads the shared link,
//  opens the App Group store without CloudKit and shows `ShareRootView` in a
//  `UIHostingController`. Everything else lives in files shared with the app.
//

import OSLog
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private static let logger = Logger(subsystem: "com.aliakseiartsimuk.shoppingplanner.ShareExtension",
                                       category: "Share")

    /// Built for each request and released with it: never cached in a `static`, the system
    /// may reuse the process and the data would be stale (B.4 p.1).
    private var container: ModelContainer?
    private var hosting: UIHostingController<ShareRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        Task { await load() }
    }

    private func load() async {
        let (urls, texts, page) = await readAttachments()
        let screen: ShareScreen
        switch ShareInput.from(urls: urls, texts: texts, page: page) {
        case .unsupported:
            screen = .unsupported
        case .link(let payload):
            if let model = makeModel(for: payload) {
                screen = .compose(model)
            } else {
                screen = .unavailable
            }
        }
        show(screen)
    }

    /// The compose model on the shared store, or `nil` when the store can't be opened
    /// (no App Group in this build, or an error): "isn't available right now".
    private func makeModel(for payload: SharePayload) -> ShareComposerModel? {
        let groupFolder = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SyncConfig.appGroupIdentifier)
        guard let location = StoreLocation.forShareExtension(appGroupContainer: groupFolder) else {
            Self.logger.error("No App Group container")
            return nil
        }
        do {
            let container = try Persistence.makeContainer(at: location)
            self.container = container
            let context = container.mainContext
            // The app reads the history of this author (ShareInbox, SE-10b).
            context.author = ShareInbox.author
            let defaults = SharedDefaults.appGroup
            let mainCurrency = SharedDefaults.mainCurrencyCode(in: defaults, locale: .current)
            let store = PlannerStore(context: context, defaultCurrencyCode: mainCurrency)
            return ShareComposerModel(
                payload: payload, store: store, shareDefaults: ShareDefaults(defaults: defaults),
                mainCurrencyCode: mainCurrency,
                titleFetcher: LPLinkMetadataFetcher(timeout: LPLinkMetadataFetcher.shareExtensionTimeout,
                                                    loadsImage: false),
                imageLoader: ShareImageDownloader())
        } catch {
            Self.logger.error("Opening the store failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func show(_ screen: ShareScreen) {
        let root = ShareRootView(
            screen: screen,
            onSave: { [weak self] in
                ShareSignal.post()
                self?.finish()
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
                self?.container = nil
            })
        let hosting = UIHostingController(rootView: root)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        self.hosting = hosting
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
        container = nil
    }

    /// `public.url` and `public.plain-text` items of the request, and Safari's preprocessing
    /// result (`com.apple.property-list`, SE-01a).
    private func readAttachments() async -> (urls: [URL], texts: [String], page: SharePage?) {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        var urls: [URL] = []
        var page: SharePage?
        // Safari (and many apps) put the page title into the item itself.
        var texts = items.flatMap { [$0.attributedContentText?.string, $0.attributedTitle?.string] }.compactMap { $0 }
        for provider in providers {
            // Safari with the JavaScript preprocessing: a dictionary, often next to the URL.
            if page == nil, provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
               let item = try? await provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier) as? NSDictionary,
               let results = item[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
                page = SharePage(results: results)
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                urls.append(url)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                texts.append(text)
            }
        }
        return (urls, texts, page)
    }
}
