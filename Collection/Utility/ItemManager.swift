//
//  ItemManager.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/6.
//

import CoreData
import UniformTypeIdentifiers
import UIKit

typealias AudioRecord = (name: String?, url: URL, duration: TimeInterval?)

enum ImportError: Error {
    case invalidData, invalidURL
    case unsupportedType
    case inaccessibleFile
    case unfoundDefaultBoard
}

final class ItemManager {
    static let shared = ItemManager()

    // MARK: - Properties

    let storageProvider: StorageProvider
    let thumbnailProvider: ThumbnailProvider

    lazy var defaultBoardID: ObjectID? = {
        guard
            let url = URL(string: UserDefaults.defaultBoardURL),
            let boardID = storageProvider.persistentContainer.persistentStoreCoordinator
                .managedObjectID(forURIRepresentation: url)
        else { return nil }

        return boardID
    }()

    // MARK: - Initializers

    init(storageProvider: StorageProvider = .shared, thumbnailProvider: ThumbnailProvider = ThumbnailProvider()) {
        self.storageProvider = storageProvider
        self.thumbnailProvider = thumbnailProvider
    }

    // MARK: - Methods

    func addNote(name: String, note: String, saveInto boardID: ObjectID) async throws {
        // TODO: throwable
        addItem(
            name: name,
            contentType: UTType.utf8PlainText.identifier,
            note: note,
            boardID: boardID,
            context: storageProvider.newTaskContext())
    }

    func updateNote(itemID: ObjectID, name: String, note: String) async throws {
        try await updateItem(
            itemID: itemID,
            name: name,
            note: note,
            context: storageProvider.newTaskContext())
    }

    func updatePreviewingItem(itemID: ObjectID, url: URL) async throws {
        let data = try Data(contentsOf: url)
        let thumbnailData = try? await thumbnailProvider.generateThumbnailData(url: url).get()

        try await updateItem(
            itemID: itemID,
            itemData: data,
            thumbnailData: thumbnailData,
            context: storageProvider.newTaskContext())
    }

    func process(_ urls: [URL], saveInto boardID: ObjectID, isSecurityScoped: Bool = true) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {[unowned self] in
                    try await processFile(url, saveInto: boardID, isSecurityScoped: isSecurityScoped)
                }
            }

            try await group.next()
        }
    }

    func process(_ itemProviders: [NSItemProvider], saveInto boardID: ObjectID? = nil, isSecurityScoped: Bool = true) async throws {
        let boardID = try unwrappedBoardID(of: boardID)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for provider in itemProviders {
                group.addTask {[unowned self] in
                    print("#\(#function): start handling items with types:", provider.registeredTypeIdentifiers)
                    guard
                        provider.hasItemConformingToTypeIdentifier(UTType.data.identifier),
                        provider.registeredTypeIdentifiers.contains(where: { UTType($0) != nil })
                    else {
                        throw ImportError.unsupportedType
                    }

                    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                        && !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        try await processURL(provider: provider, saveInto: boardID)
                        return
                    }

                    if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                        try await processText(provider: provider, saveInto: boardID)
                        return
                    }

                    try await processFile(provider: provider, saveInto: boardID, isSecurityScoped: isSecurityScoped)
                }
            }

            try await group.next()
        }
    }

    func process(_ image: UIImage, saveInto boardID: ObjectID) async {
        // TODO: throwable
        let data = image.jpegData(compressionQuality: 1)

        let thumbnail = image.preparingThumbnail(of: CGSize(width: 400, height: 400))
        let thumbnailData = thumbnail?.pngData()

        let currentTime = DateFormatter.hyphenatedDateTimeFormatter.string(from: Date())
        let name = "Photo \(currentTime)"

        addItem(
            name: name,
            contentType: UTType.jpeg.identifier,
            itemData: data,
            thumbnailData: thumbnailData,
            boardID: boardID,
            context: storageProvider.newTaskContext())
    }

    func process(_ record: AudioRecord, saveInto boardID: ObjectID) async throws {
        var nserror: NSError?
        var error: Error?

        NSFileCoordinator().coordinate(readingItemAt: record.url, error: &nserror) { url in
            guard
                let data = try? Data(contentsOf: url),
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey]),
                let size = values.fileSize,
                size <= 50_000_000,
                let type = values.contentType
            else {
                error = ImportError.invalidData
                return
            }

            var filename = record.name ?? ""
            if record.name == nil {
                let currentTime = DateFormatter.hyphenatedDateTimeFormatter.string(from: Date())
                filename = "Voice \(currentTime)"
            }

            addItem(
                name: filename,
                contentType: type.identifier,
                itemData: data,
                boardID: boardID,
                context: storageProvider.newTaskContext())
        }

        if let error = error {
            throw error
        }

        if let nserror = nserror {
            throw nserror
        }
    }
}

// MARK: - Private

extension ItemManager {
    private func processURL(provider: NSItemProvider, saveInto boardID: ObjectID) async throws {
        guard let url = try await provider.loadObject(ofClass: URL.self) else {
            throw ImportError.invalidData
        }

        addItem(
            name: url.absoluteString,
            contentType: UTType.url.identifier,
            itemData: url.dataRepresentation,
            boardID: boardID,
            context: storageProvider.newTaskContext()
        )
    }

    private func processText(provider: NSItemProvider, saveInto boardID: ObjectID) async throws {
        guard let data = try await provider.loadDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier)
        else { throw ImportError.invalidData }

        let currentTime = DateFormatter.hyphenatedDateTimeFormatter.string(from: Date())
        let name = "Note \(currentTime)"

        addItem(
            name: name,
            contentType: UTType.utf8PlainText.identifier,
            note: String(data: data, encoding: .utf8),
            boardID: boardID,
            context: storageProvider.newTaskContext()
        )
    }

    private func processFile(provider: NSItemProvider, saveInto boardID: ObjectID, isSecurityScoped: Bool) async throws {
        guard let typeIdentifier = provider.registeredTypeIdentifiers
            .compactMap({ UTType($0) })
            .first(where: { type in
                let isLivePhotoType = type.conforms(to: UTType.heif)
                    || type.conforms(to: .livePhoto)
                    || type.conforms(to: .livePhotoBundle)

                return (type.isPublic || type.isDeclared) && !isLivePhotoType
            })?
            .identifier
        else {
            throw ImportError.unsupportedType
        }
        print("#start process file type", typeIdentifier)

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url = url else {
                    continuation.resume(throwing: ImportError.invalidURL)
                    return
                }

                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    var errorIfAny: Error?
                    do {
                        try await self.processFile(url, saveInto: boardID, isSecurityScoped: isSecurityScoped)
                    } catch {
                        errorIfAny = error
                    }
                    if let errorIfAny = errorIfAny {
                        continuation.resume(throwing: errorIfAny)
                    } else {
                        continuation.resume()
                    }
                    semaphore.signal()
                }

                semaphore.wait()
            }
        }
    }

    private func processFile(_ url: URL, saveInto boardID: ObjectID, isSecurityScoped: Bool) async throws {
        if isSecurityScoped {
            guard url.startAccessingSecurityScopedResource() else {
                throw ImportError.inaccessibleFile
            }
        }

        defer { url.stopAccessingSecurityScopedResource() }

        var nserror: NSError?
        var error: Error?

        NSFileCoordinator().coordinate(readingItemAt: url, error: &nserror) { url in
            guard
                let values = try? url.resourceValues(forKeys: [.nameKey, .fileSizeKey, .contentTypeKey]),
                let size = values.fileSize,
                size <= 50_000_000,
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

                addItem(
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

    private func unwrappedBoardID(of boardID: ObjectID?) throws -> ObjectID {
        var boardID = boardID

        if boardID == nil {
            boardID = defaultBoardID
        }

        guard let boardID = boardID else {
            throw ImportError.unfoundDefaultBoard
        }

        return boardID
    }
}

// MARK: - CoreData Methods

extension ItemManager {
    private func addItem(
        name: String,
        contentType: String,
        note: String? = nil,
        itemData: Data? = nil,
        thumbnailData: Data? = nil,
        boardID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) {
        context.perform {
            let item = Item(context: context)
            item.name = name
            item.contentType = contentType
            item.note = note
            item.uuid = UUID()

            let thumbnail = Thumbnail(context: context)
            thumbnail.data = thumbnailData
            thumbnail.item = item

            let itemDataObject = ItemData(context: context)
            itemDataObject.data = itemData
            itemDataObject.item = item

            let currentDate = Date()
            item.creationDate = currentDate
            item.updateDate = currentDate

            if let board = context.object(with: boardID) as? Board {
                board.addToItems(item)
            }

            context.save(situation: .addItem)
        }
    }

    private func updateItem(
        itemID: NSManagedObjectID,
        name: String? = nil,
        note: String? = nil,
        itemData: Data? = nil,
        thumbnailData: Data? = nil,
        boardID: NSManagedObjectID? = nil,
        context: NSManagedObjectContext
    ) async throws {
        guard let item = try context.existingObject(with: itemID) as? Item else {
            throw ItemError.unfoundItem
        }

        try await context.perform {
            if let name = name {
                item.name = name
            }
            if let note = note {
                item.note = note
            }
            if let itemData = itemData, let itemDataObject = item.itemData {
                itemDataObject.data = itemData
            }
            if let thumbnailData = thumbnailData, let thumbnail = item.thumbnail {
                thumbnail.data = thumbnailData
            }
            if let boardID = boardID, let board = try context.existingObject(with: boardID) as? Board {
                board.addToItems(item)
            }

            let currentDate = Date()
            item.updateDate = currentDate

            context.save(situation: .updateItem)
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
