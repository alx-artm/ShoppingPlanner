//
//  TipJarView.swift
//  Project2
//
//  Spec 12 "Экран Tip Jar": an honest text, three tips from the App Store and the
//  states loading / error / purchasing / pending / thank-you. Pushed from Settings,
//  so on iPad it stays inside the Settings sheet (TJ-23). No prompts anywhere else.
//

import SwiftUI

struct TipJarView: View {
    @Environment(TipJar.self) private var tipJar

    var body: some View {
        List {
            Section {
                Text("Shopping Planner is made by one developer. If it helps you, you can leave a tip. Tips don't unlock anything — every feature stays free.")
            }

            if tipJar.showsThankYou {
                Section {
                    TipThankYouCard()
                }
            }

            if tipJar.isPending {
                Section {
                    Label("Waiting for approval", systemImage: "clock")
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("tipJar.pending")
                }
            }

            switch tipJar.phase {
            case .idle, .loading:
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("tipJar.loading")
                }
            case .loaded:
                Section {
                    ForEach(tipJar.products) { product in
                        TipProductRow(product: product)
                    }
                }
            case .unavailable(let reason):
                Section {
                    Text(reason.message)
                        .accessibilityIdentifier("tipJar.error")
                    Button("Try Again") {
                        Task { await tipJar.loadProducts() }
                    }
                    .accessibilityIdentifier("tipJar.retryButton")
                }
            }
        }
        .accessibilityIdentifier("tipJar.list")
        .navigationTitle("Support the Developer")
        .navigationBarTitleDisplayMode(.inline)
        .alert(Text(tipJar.alert?.title ?? ""), isPresented: isAlertShown, presenting: tipJar.alert) { _ in
            Button("OK") {}
                .accessibilityIdentifier("tipJar.alert.ok")
        } message: { alert in
            if let message = alert.message { Text(message) }
        }
        .onAppear { tipJar.isScreenVisible = true }
        .onDisappear { tipJar.screenDidDisappear() }
        .task { await tipJar.loadProductsIfNeeded() }
    }

    private var isAlertShown: Binding<Bool> {
        Binding(
            get: { tipJar.alert != nil },
            set: { if !$0 { tipJar.alert = nil } }
        )
    }
}

/// One tip: symbol, name and App Store price; the price moves under the name at
/// accessibility sizes (TJ-21). VoiceOver reads "Coffee, $0.99, Button" (TJ-20).
private struct TipProductRow: View {
    @Environment(TipJar.self) private var tipJar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let product: TipProduct

    var body: some View {
        Button {
            Task { await tipJar.purchase(product) }
        } label: {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Label {
                    Text(verbatim: product.displayName)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: product.kind?.systemImage ?? "heart")
                        .accessibilityHidden(true)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if tipJar.purchasingProductID == product.id {
                    ProgressView()
                } else {
                    Text(verbatim: product.displayPrice)
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                }
            }
        }
        .disabled(tipJar.isPurchasing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(product.displayName), \(product.displayPrice)"))
        .accessibilityHint(Text("Leaves a tip. Doesn't unlock anything."))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(product.kind?.accessibilityIdentifier ?? "tipJar.product.\(product.id)")
    }
}

/// "Thank you! ♥ Your support means a lot." VoiceOver hears it via the announcement
/// `TipJar` posts (TJ-20).
private struct TipThankYouCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("Thank you!")
                    .font(.headline)
            } icon: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .accessibilityHidden(true)
            }
            Text("Your support means a lot.")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tipJar.thankYou")
    }
}

private extension TipJar.Unavailable {
    var message: LocalizedStringResource {
        switch self {
        case .loadFailed: "Couldn't load tips. Check your connection and try again."
        case .noProducts: "Tips are unavailable right now."
        }
    }
}

private extension TipJar.Alert {
    var title: LocalizedStringResource {
        switch self {
        case .purchaseFailed: "Purchase failed. Please try again."
        case .unverified: "Purchase couldn't be verified"
        }
    }

    var message: LocalizedStringResource? {
        switch self {
        case .purchaseFailed: nil
        case .unverified: "You were not charged twice — contact support if needed."
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TipJarView()
    }
    .environment(TipJar(store: ScriptedTipJarStore(scenario: .success), defaults: .init(suiteName: "preview") ?? .standard))
}
#endif
