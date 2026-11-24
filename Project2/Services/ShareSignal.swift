//
//  ShareSignal.swift
//  Project2
//
//  "The Share Extension just saved an item" (spec 06 B.4 p.2, SE-10a): a Darwin notification
//  from the extension to the app. The app and the extension are two processes with two
//  containers on one store file, so the app's `@Query` doesn't learn about the new item by
//  itself. On iPad in Split View the app stays active the whole time, so `scenePhase` alone
//  is not enough: this signal makes `ShareInbox` look right away.
//
//  A Darwin notification carries no data and needs no entitlement; it only wakes the
//  observer, which then reads the store's history.
//

import Foundation

enum ShareSignal {
    static let name = "com.aliakseiartsimuk.shoppingplanner.shareSaved"

    /// Called by the extension after a successful save.
    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// The app's handler. A C callback can't capture context, so it lives here.
    @MainActor private static var handler: (@MainActor () -> Void)?

    /// Starts calling `handler` on the main actor for every signal. One observer per process.
    @MainActor
    static func observe(_ handler: @escaping @MainActor () -> Void) {
        let isFirst = self.handler == nil
        self.handler = handler
        guard isFirst else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in
                Task { @MainActor in ShareSignal.handler?() }
            },
            name as CFString, nil, .deliverImmediately)
    }
}
