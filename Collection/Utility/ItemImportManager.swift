//
//  ItemImportManager.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/6.
//

import CoreData
import UniformTypeIdentifiers
import UIKit

enum ImportError: Error {
    case invalidData, invalidURL
    case unsupportedType
    case inaccessibleFile
}

actor ErrorStore {
    var errors: [Error] = []
    func append(_ error: Error) {
        errors.append(error)
    }
}

struct ItemImportManager {
    // MARK: - Properties

    let storageProvider: StorageProvider
    let thumbnailProvider: ThumbnailProvider
    let boardID: NSManagedObjectID

    // MARK: - Initializers

    init(storageProvider: StorageProvider, thumbnailProvider: ThumbnailProvider, boardID: NSManagedObjectID) {
        self.storageProvider = storageProvider
        self.thumbnailProvider = thumbnailProvider
        self.boardID = boardID
    }

    init(storageProvider: StorageProvider, boardID: NSManagedObjectID) {
        self.init(
            storageProvider: storageProvider,
            thumbnailProvider: ThumbnailProvider(),
            boardID: boardID)
    }

    // MARK: - Methods

    func process(_ urls: [URL]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else {
                    throw ImportError.inaccessibleFile
                }

                group.addTask {
                    try await readAndSave(url)
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try await group.next()
        }
    }

    func process(_ itemProviders: [NSItemProvider]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for provider in itemProviders {
                print("#\(#function): start handling items with types:", provider.registeredTypeIdentifiers)
                guard
                    provider.hasItemConformingToTypeIdentifier(UTType.data.identifier),
                    let type = provider.registeredTypeIdentifiers.first(where: { UTType($0) != nil })
                else {
                    throw ImportError.unsupportedType
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                    && !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    group.addTask {
                        try await processURL(provider: provider)
                    }
                    continue
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                    group.addTask {
                        try await processText(provider: provider)
                    }
                    continue
                }

                group.addTask {
                    // FIXME: collect error inside async block
                    let errorStore = ErrorStore()
//                    let semaphore = DispatchSemaphore(value: 0)

                    provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                        if let error = error {
                            Task {
                                await errorStore.append(error)
//                                semaphore.signal()
                            }
                            return
                        }

                        guard let url = url else {
                            Task {
                                await errorStore.append(ImportError.invalidURL)
//                                semaphore.signal()
                            }
                            return
                        }

                        let innerSemaphore = DispatchSemaphore(value: 0)

                        Task {
                            do {
                                try await readAndSave(url)
                            } catch {
                                await errorStore.append(error)
                                innerSemaphore.signal()
//                                semaphore.signal()
                            }
                        }

                        innerSemaphore.wait()
                    }

//                    semaphore.wait()

                    if let error = await errorStore.errors.first {
                        throw error
                    }
                }
            }

            try await group.next()
        }
    }
}

// MARK: - Private

extension ItemImportManager {
    private func processURL(provider: NSItemProvider) async throws {
        guard let url = try await provider.loadObject(ofClass: URL.self) else {
            throw ImportError.invalidData
        }

        storageProvider.addItem(
            name: url.absoluteString,
            contentType: UTType.url.identifier,
            itemData: url.dataRepresentation,
            boardID: boardID,
            context: storageProvider.newTaskContext()
        )
    }

    private func processText(provider: NSItemProvider) async throws {
        guard let data = try await provider.loadDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier)
        else { throw ImportError.invalidData }

        let currentTime = DateFormatter.hyphenatedDateTimeFormatter.string(from: Date())
        let name = "Note \(currentTime)"

        self.storageProvider.addItem(
            name: name,
            contentType: UTType.utf8PlainText.identifier,
            note: String(data: data, encoding: .utf8),
            boardID: boardID,
            context: storageProvider.newTaskContext()
        )
    }


    private func readAndSave(_ url: URL) async throws {
        var nserror: NSError?
        var error: Error?

        NSFileCoordinator().coordinate(readingItemAt: url, error: &nserror) { url in
            guard
                let values = try? url.resourceValues(forKeys: [.nameKey, .fileSizeKey, .contentTypeKey]),
                let size = values.fileSize,
                size <= 20_000_000,
                let type = values.contentType,
                let name = values.name,
                let data = try? Data(contentsOf: url)
            else {
                error = ImportError.invalidData
                return
            }

            let semaphore = DispatchSemaphore(value: 0)

            Task {
                defer { semaphore.signal() }

                let thumbnailResult = await thumbnailProvider.generateThumbnailData(url: url)

                var thumbnailData: Data?

                switch thumbnailResult {
                case .success(let data):
                    thumbnailData = data
                case .failure(let error):
                    print("#\(#function): Failed to generate thumbnail data, \(error)")
                }

                storageProvider.addItem(
                    name: name,
                    contentType: type.identifier,
                    itemData: data,
                    thumbnailData: thumbnailData,
                    boardID: boardID,
                    context: storageProvider.newTaskContext()
                )
            }

            semaphore.wait()
        }

        if let error = error {
            throw error
        }

        if let nserror = nserror {
            throw nserror
        }
    }
}

// MARK: - NSItemProvider+Sendable

extension NSItemProvider: @unchecked Sendable {}

// MARK: - NSItemProvider+async/await wrapper

extension NSItemProvider {
    func loadDataRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> Data? {
        return try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }
    func loadObject<T>(ofClass: T.Type) async throws -> T? where T: _ObjectiveCBridgeable, T._ObjectiveCType: NSItemProviderReading {
        return try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: ofClass) { object, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: object)
                }
            }
        }
    }
}
