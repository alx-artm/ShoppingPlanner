//
//  StoreMigrator.swift
//  Project2
//
//  M6: the store moves from the app's own Application Support folder to the
//  App Group folder (spec 01 "Sync"), so the Share Extension (M7) can open it.
//
//  Which stores this actually moves: only stores of THIS bundle id. Builds of the
//  old bundle id (`…Project2`, before DECISIONS Р-31) are another app with
//  another sandbox; their data can't be reached from here. In practice it moves
//  a store written by a build without the App Group entitlement (an unsigned
//  build, like CI's) once a signed build runs on the same simulator / device.
//

import Foundation

enum StoreMigrator {

    enum Outcome: Equatable {
        /// No store in the old folder (or the two folders are the same).
        case nothingToMove
        /// A store already exists in the new folder: it wins, the old files stay untouched.
        case destinationExists
        /// These files and folders were moved.
        case moved([String])
    }

    /// The SQLite file, its journal files, and the folder SwiftData keeps
    /// `.externalStorage` data in (link thumbnails, `ItemModel.linkImageData`).
    static func fileNames(storeName: String) -> [String] {
        ["\(storeName).store", "\(storeName).store-shm", "\(storeName).store-wal", ".\(storeName)_SUPPORT"]
    }

    /// Moves the store named `storeName` from `source` to `destination` if it is only in `source`.
    ///
    /// Copy first, then delete: if a copy fails, the copies made so far are removed and the
    /// error is thrown, so the store stays complete in `source` and the next launch tries again.
    /// Must run before any container opens either store.
    static func moveStoreIfNeeded(named storeName: String, from source: URL, to destination: URL,
                                  fileManager: FileManager = .default) throws -> Outcome {
        let names = fileNames(storeName: storeName)
        guard source.standardizedFileURL != destination.standardizedFileURL,
              fileManager.fileExists(atPath: source.appending(path: names[0]).path) else {
            return .nothingToMove
        }
        guard !fileManager.fileExists(atPath: destination.appending(path: names[0]).path) else {
            return .destinationExists
        }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let present = names.filter { fileManager.fileExists(atPath: source.appending(path: $0).path) }
        var copied: [String] = []
        do {
            for name in present {
                try fileManager.copyItem(at: source.appending(path: name), to: destination.appending(path: name))
                copied.append(name)
            }
        } catch {
            for name in copied {
                try? fileManager.removeItem(at: destination.appending(path: name))
            }
            throw error
        }
        // The copy is complete; a leftover old file is harmless (the new folder wins next time).
        for name in present {
            try? fileManager.removeItem(at: source.appending(path: name))
        }
        return .moved(present)
    }
}
