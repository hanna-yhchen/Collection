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
}

actor ImportErrorBag {
    var errors: [Error] = []
    func append(_ error: Error) {
        errors.append(error)
    }
}

final class ItemImportManager {
    // MARK: - Properties

    let storageProvider: StorageProvider
    let thumbnailProvider: ThumbnailProvider
    let boardID: NSManagedObjectID

    var completion: ((Error?) -> Void)?

    // MARK: - Initializers

    init(storageProvider: StorageProvider, thumbnailProvider: ThumbnailProvider, boardID: NSManagedObjectID) {
        self.storageProvider = storageProvider
        self.thumbnailProvider = thumbnailProvider
        self.boardID = boardID
    }

    convenience init(storageProvider: StorageProvider, boardID: NSManagedObjectID) {
        self.init(
            storageProvider: storageProvider,
            thumbnailProvider: ThumbnailProvider(),
            boardID: boardID)
    }

    // MARK: - Methods

    func process(_ urls: [URL], completion: @escaping (Error?) -> Void) {
        // TODO: tackle batch import
        let group = DispatchGroup()
        let errorBag = ImportErrorBag()

        urls.forEach { url in
            group.enter()

            Task {
                guard (await errorBag.errors).isEmpty else {
                    group.leave()
                    return
                }

                if let error = await self.readAndSave(url) {
                    await errorBag.append(error)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            Task {
                completion(await errorBag.errors.first)
            }
        }
    }

    func process(_ itemProviders: [NSItemProvider], completion: @escaping (Error?) -> Void) {
        itemProviders.forEach { provider in
            guard
                provider.hasItemConformingToTypeIdentifier(UTType.data.identifier),
                let type = provider.registeredTypeIdentifiers.first(where: { identifier in
                    UTType(identifier) != nil
                })
            else {
                // TODO: show failure alert
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                let currentTime = DateFormatter.hyphenatedDateTimeFormatter.string(from: Date())
                let name = "Pasted \(currentTime)"

                provider.loadObject(ofClass: URL.self) {[weak self]  url, error in
                    guard let `self` = self else { return }
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
                    completion(error)
                }.resume()

                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                let currentTime = DateFormatter.hyphenatedDateTimeFormatter.string(from: Date())
                let name = "Pasted \(currentTime)"

                provider.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) {[weak self] data, error in
                    guard let `self` = self else { return }
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
                    completion(error)
                }
                return
            }

            provider.loadFileRepresentation(forTypeIdentifier: type) {[weak self] url, error in
                guard let `self` = self else { return }

                if let error = error {
                    print("#\(#function): Error loading data from pasteboard, \(error)")
                    return
                }

                guard let url = url else {
                    print("#\(#function): Failed to retrieve url for loaded file")
                    return
                }

                Task {
                    let error = await self.readAndSave(url)
                    completion(error)
                }
            }
        }
    }

    func processPasteboard(itemProviders: [NSItemProvider], completion: @escaping (Error?) -> Void) {
        itemProviders.forEach { provider in
            guard
                provider.hasItemConformingToTypeIdentifier(UTType.data.identifier)
            else {
                // TODO: show failure alert
                return
            }

            // TODO: abstract early return logic
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                guard
                    let urlString = UIPasteboard.general.string,
                    let data = urlString.data(using: .utf8)
                else {
                    // TODO: show failure alert
                    return
                }

                storageProvider.addItem(
                    name: urlString,
                    contentType: UTType.url.identifier,
                    itemData: data,
                    boardID: boardID,
                    context: storageProvider.newTaskContext()
                )
                return
            }


            if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                let text = UIPasteboard.general.string
                let currentTime = DateFormatter.hyphenatedDateTimeFormatter.string(from: Date())
                let name = "Pasted \(currentTime)"
                storageProvider.addItem(
                    name: name,
                    contentType: UTType.plainText.identifier,
                    note: text,
                    boardID: boardID,
                    context: storageProvider.newTaskContext()
                )
                return
            }

            process([provider], completion: completion)
        }
    }

    // MARK: - Private

    private func readAndSave(_ url: URL) async -> NSError? {
        // FIXME: cannot access photo url when imported by share extension
        guard url.startAccessingSecurityScopedResource() else {
            // TODO: pass error msg and show alert
            return nil
        }

        defer { url.stopAccessingSecurityScopedResource() }

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
                // TODO: pass error msg and show alert
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
            print("#\(#function): Error reading input data, \(error)")
        }

        return error
    }
}
