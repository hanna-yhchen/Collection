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
    case invalidData
    case unsupportedType
    case inaccessibleFile
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

    func process(_ urls: [URL], completion: @escaping (Error?) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var errors: [Error] = []

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                completion(ImportError.inaccessibleFile)
                break
            }

            group.enter()

            DispatchQueue.global().async {
                readAndSave(url) { error in
                    if let error = error {
                        lock.with { errors.append(error) }
                    }
                    url.stopAccessingSecurityScopedResource()
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let errorIfAny = errors.first
            completion(errorIfAny)
        }
    }

    func process(_ itemProviders: [NSItemProvider], completion: @escaping (Error?) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var errors: [Error] = []

        for provider in itemProviders {
            group.enter()
            print("#\(#function): start handling items with types:", provider.registeredTypeIdentifiers)

            guard
                provider.hasItemConformingToTypeIdentifier(UTType.data.identifier),
                let type = provider.registeredTypeIdentifiers.first(where: { identifier in
                    UTType(identifier) != nil
                })
            else {
                completion(ImportError.unsupportedType)
                group.leave()
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                && !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadObject(ofClass: URL.self) { url, error in
                    if let error = error {
                        completion(error)
                        return
                    }

                    guard let url = url else {
                        completion(ImportError.invalidData)
                        return
                    }

                    self.storageProvider.addItem(
                        name: url.absoluteString,
                        contentType: UTType.url.identifier,
                        itemData: url.dataRepresentation,
                        boardID: self.boardID,
                        context: self.storageProvider.newTaskContext()
                    )

                    group.leave()
                }
                .resume()

                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                let currentTime = DateFormatter.hyphenatedDateTimeFormatter.string(from: Date())
                let name = "Note \(currentTime)"

                provider.loadDataRepresentation(
                    forTypeIdentifier: UTType.utf8PlainText.identifier
                ) { data, error in
                    if let error = error {
                        completion(error)
                        return
                    }

                    guard let data = data else {
                        completion(ImportError.invalidData)
                        return
                    }

                    self.storageProvider.addItem(
                        name: name,
                        contentType: UTType.plainText.identifier,
                        note: String(data: data, encoding: .utf8),
                        boardID: self.boardID,
                        context: self.storageProvider.newTaskContext()
                    )

                    group.leave()
                }

                return
            }

            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                if let error = error {
                    print("#\(#function): Error loading data from pasteboard, \(error)")
                    return
                }

                guard let url = url else {
                    print("#\(#function): Failed to retrieve url for loaded file")
                    return
                }

                let semaphore = DispatchSemaphore(value: 0)

                self.readAndSave(url) { error in
                    if let error = error {
                        completion(error)
                    }
                    semaphore.signal()
                }

                semaphore.wait()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let errorIfAny = errors.first
            completion(errorIfAny)
        }
    }

    // MARK: - Private

    private func processURL(provider: NSItemProvider) async throws {
        guard let url = try await provider.loadObject(ofClass: URL.self) else {
            throw ImportError.invalidData
        }

        storageProvider.addItem(
            name: url.absoluteString,
            contentType: UTType.url.identifier,
            itemData: url.dataRepresentation,
            boardID: self.boardID,
            context: self.storageProvider.newTaskContext()
        )
    }

    private func readAndSave(_ url: URL, completion: @escaping (Error?) -> Void) {
        var error: NSError?

        NSFileCoordinator().coordinate(readingItemAt: url, error: &error) { url in
            guard
                let values = try? url.resourceValues(forKeys: [.nameKey, .fileSizeKey, .contentTypeKey]),
                let size = values.fileSize,
                size <= 20_000_000,
                let type = values.contentType,
                let name = values.name,
                let data = try? Data(contentsOf: url)
            else {
                completion(ImportError.invalidData)
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

                completion(nil)
            }

            semaphore.wait()
        }

        if let error = error {
            completion(error)
        }
    }
}

extension NSItemProvider: @unchecked Sendable {}

extension NSLock {
    @discardableResult
    func with<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}

extension NSItemProvider {
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
