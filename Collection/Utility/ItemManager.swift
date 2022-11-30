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

actor TaskCounter {
    var count = 0

    func increment() {
        count += 1
    }

    func decrement() {
        count -= 1
    }
}

final class ItemManager {
    static let shared = ItemManager()

    // MARK: - Properties

    private let storageProvider: StorageProvider
    private let thumbnailProvider: ThumbnailProvider

    private lazy var defaultBoardID: ObjectID? = {
        guard
            let url = URL(string: UserDefaults.defaultBoardURL),
            let boardID = storageProvider.persistentContainer.persistentStoreCoordinator
                .managedObjectID(forURIRepresentation: url)
        else { return nil }

        return boardID
    }()

    private lazy var fileCoordinator = NSFileCoordinator()

    // MARK: - Initializers

    init(storageProvider: StorageProvider = .shared, thumbnailProvider: ThumbnailProvider = ThumbnailProvider()) {
        self.storageProvider = storageProvider
        self.thumbnailProvider = thumbnailProvider
    }

    // MARK: - Methods

    // TODO: could be replaced by general core data method?
    func addNote(name: String, note: String, saveInto boardID: ObjectID) async throws {
        // TODO: throwable
        addItem(
            name: name,
            displayType: .note,
            uti: UTType.utf8PlainText.identifier,
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
            let taskCounter = TaskCounter()

            for url in urls {
                while await taskCounter.count >= 3 {
                    try await group.next()
                }

                await taskCounter.increment()

                group.addTask {[unowned self] in
                    try processFile(url, saveInto: boardID, isSecurityScoped: isSecurityScoped)
                    await taskCounter.decrement()
                }
            }

            try await group.next()
        }
    }

    func process(_ itemProviders: [NSItemProvider], saveInto boardID: ObjectID? = nil, isSecurityScoped: Bool = true) async throws {
        let boardID = try unwrappedBoardID(of: boardID)

        try await withThrowingTaskGroup(of: Void.self) { group in
            let taskCounter = TaskCounter()

            for provider in itemProviders {
                while await taskCounter.count >= 3 {
                    try await group.next()
                }

                await taskCounter.increment()

                group.addTask {[unowned self] in
                    print("#\(#function): start handling items with types:", provider.registeredTypeIdentifiers)
                    guard
                        provider.hasItemConformingToTypeIdentifier(UTType.data.identifier),
                        provider.registeredTypeIdentifiers.contains(where: { UTType($0) != nil })
                    else {
                        await taskCounter.decrement()
                        throw ImportError.unsupportedType
                    }

                    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                        && !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        try await processURL(provider: provider, saveInto: boardID)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                        try await processText(provider: provider, saveInto: boardID)
                    } else {
                        try await processFile(provider: provider, saveInto: boardID, isSecurityScoped: isSecurityScoped)
                    }

                    await taskCounter.decrement()
                }
            }

            try await group.next()
        }
    }

    func process(_ image: UIImage, saveInto boardID: ObjectID) async {
        // TODO: throwable
        let data = image.jpegData(compressionQuality: 1)

        let thumbnail = image.preparingThumbnail(of: CGSize(width: 400, height: 400))
        let thumbnailData = thumbnail?.jpegData(compressionQuality: 1)

        addItem(
            displayType: .image,
            uti: UTType.jpeg.identifier,
            itemData: data,
            thumbnailData: thumbnailData,
            boardID: boardID,
            context: storageProvider.newTaskContext())
    }

    func process(_ record: AudioRecord, saveInto boardID: ObjectID) async throws {
        var nserror: NSError?
        var error: Error?

        fileCoordinator.coordinate(readingItemAt: record.url, error: &nserror) { url in
            guard
                let data = try? Data(contentsOf: url),
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey]),
                let size = values.fileSize,
                size <= 50_000_000,
                let uti = values.contentType?.identifier
            else {
                error = ImportError.invalidData
                return
            }

            addItem(
                name: record.name,
                displayType: .audio,
                uti: uti,
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
            displayType: .link,
            uti: UTType.url.identifier,
            itemData: url.dataRepresentation,
            boardID: boardID,
            context: storageProvider.newTaskContext()
        )
    }

    private func processText(provider: NSItemProvider, saveInto boardID: ObjectID) async throws {
        guard let data = try await provider.loadDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier)
        else { throw ImportError.invalidData }

        addItem(
            displayType: .note,
            uti: UTType.utf8PlainText.identifier,
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
        print("#\(#function) start process file type:", typeIdentifier)

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) {[unowned self] url, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url = url else {
                    continuation.resume(throwing: ImportError.invalidURL)
                    return
                }

                do {
                    try processFile(url, saveInto: boardID, isSecurityScoped: isSecurityScoped)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func processFile(_ url: URL, saveInto boardID: ObjectID, isSecurityScoped: Bool) throws {
        if isSecurityScoped {
            guard url.startAccessingSecurityScopedResource() else {
                throw ImportError.inaccessibleFile
            }
        }

        defer { url.stopAccessingSecurityScopedResource() }

        var nserror: NSError?
        var error: Error?

        fileCoordinator.coordinate(readingItemAt: url, error: &nserror) { url in
            guard
                let values = try? url.resourceValues(forKeys: [.nameKey, .fileSizeKey, .contentTypeKey]),
                let size = values.fileSize,
                size <= 50_000_000,
                let uti = values.contentType?.identifier,
                let data = try? Data(contentsOf: url)
            else {
                error = ImportError.invalidData
                return
            }

            let type = displayType(of: uti)
            let keepSourceName = type == .file
            let sourceName = (values.name as? NSString)?.deletingPathExtension

            let semaphore = DispatchSemaphore(value: 0)

            Task {
                defer { semaphore.signal() }

                let thumbnailData = try? await thumbnailProvider.generateThumbnailData(url: url).get()
                if thumbnailData == nil {
                    print("#\(#function): Failed to generate thumbnail data")
                }

                addItem(
                    name: keepSourceName ? sourceName : nil,
                    displayType: type,
                    uti: uti,
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

    private func displayType(of uti: String) -> DisplayType {
        guard let type = UTType(uti) else { return .file }
        if type.conforms(to: .image) {
            return .image
        } else if type.conforms(to: .url) {
            return .link
        } else if type.conforms(to: .audio) {
            return .audio
        } else if type.conforms(to: .movie) {
            return .video
        } else {
            return .file
        }
    }
}

// MARK: - CoreData Methods

extension ItemManager {
    private func addItem(
        name: String? = nil,
        displayType: DisplayType,
        uti: String,
        note: String? = nil,
        itemData: Data? = nil,
        thumbnailData: Data? = nil,
        boardID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) {
        context.perform {
            let item = Item(context: context)
            item.name = name
            item.uti = uti
            item.note = note
            item.uuid = UUID()
            item.displayType = displayType.rawValue

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

            // TODO: error handling
            try? context.save(situation: .addItem)
        }
    }

    func updateItem(
        itemID: NSManagedObjectID,
        name: String? = nil,
        note: String? = nil,
        itemData: Data? = nil,
        thumbnailData: Data? = nil,
        boardID: NSManagedObjectID? = nil,
        context: NSManagedObjectContext? = nil
    ) async throws {
        let context = context ?? storageProvider.newTaskContext()

        guard let item = try context.existingObject(with: itemID) as? Item else {
            throw CoreDataError.unfoundObjectInContext
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
                if let tags = item.tags {
                    board.addToTags(tags)
                }
            }

            let currentDate = Date()
            item.updateDate = currentDate

            try context.save(situation: .updateItem)
        }
    }

    func copyItem(
        itemID: NSManagedObjectID,
        toBoardID boardID: NSManagedObjectID,
        context: NSManagedObjectContext? = nil
    ) async throws {
        let context = context ?? storageProvider.newTaskContext()

        guard let item = try context.existingObject(with: itemID) as? Item else {
            throw CoreDataError.unfoundObjectInContext
        }

        try await context.perform {
            let copy = Item(context: context)
            copy.name = item.name
            copy.uti = item.uti
            copy.note = item.note
            copy.uuid = UUID()
            copy.displayType = item.displayType

            let thumbnail = Thumbnail(context: context)
            thumbnail.data = item.thumbnail?.data
            thumbnail.item = copy

            let itemDataObject = ItemData(context: context)
            itemDataObject.data = item.itemData?.data
            itemDataObject.item = copy

            let currentDate = Date()
            copy.creationDate = currentDate
            copy.updateDate = currentDate

            if let board = try context.existingObject(with: boardID) as? Board {
                board.addToItems(copy)
                if let tags = item.tags {
                    copy.addToTags(tags)
                    board.addToTags(tags)
                }
            }

            try context.save(situation: .copyItem)
        }
    }

    func deleteItem(
        itemID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) async throws {
        guard let item = try context.existingObject(with: itemID) as? Item else {
            throw CoreDataError.unfoundObjectInContext
        }

        try await context.perform {
            context.delete(item)
            try context.save(situation: .deleteItem)
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
