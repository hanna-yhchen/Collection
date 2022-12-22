//
//  ItemManager.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/6.
//

import CoreData
import DeviceKit
import UniformTypeIdentifiers
import UIKit

typealias AudioRecord = (name: String?, url: URL, duration: TimeInterval?)

enum ImportError: Error {
    case invalidData, invalidURL
    case unsupportedType
    case inaccessibleFile
    case unfoundDefaultBoard
}

actor ErrorActor {
    var error: Error?

    func setError(_ newError: Error) {
        error = newError
    }
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

    private lazy var queue = OperationQueue()

    private lazy var maxTaskCount: Int = {
        let oldDevices: [Device] = [.iPhone6s, .iPhone6sPlus, .iPhoneSE, .iPhone7, .iPhone7Plus, .iPhone8, .iPhone8Plus]
        if Device.current.isOneOf(oldDevices) {
            return 1
        }
        return 3
    }()

    // MARK: - Initializers

    init(storageProvider: StorageProvider = .shared, thumbnailProvider: ThumbnailProvider = ThumbnailProvider()) {
        self.storageProvider = storageProvider
        self.thumbnailProvider = thumbnailProvider
    }

    // MARK: - Methods

    // TODO: could be replaced by general core data method?
    func addNote(name: String, note: String, saveInto boardID: ObjectID) async throws {
        // TODO: throwable
        try await storageProvider.addItem(
            name: name,
            displayType: .note,
            uti: UTType.utf8PlainText.identifier,
            note: note,
            boardID: boardID,
            context: storageProvider.newTaskContext())
    }

    func updateNote(itemID: ObjectID, name: String, note: String) async throws {
        try await storageProvider.updateItem(
            itemID: itemID,
            name: name,
            note: note,
            context: storageProvider.newTaskContext())
    }

    func updatePreviewingItem(itemID: ObjectID, url: URL) async throws {
        let data = try Data(contentsOf: url)
        let thumbnailData = try? await thumbnailProvider.generateThumbnailData(url: url).get()

        try await storageProvider.updateItem(
            itemID: itemID,
            itemData: data,
            thumbnailData: thumbnailData,
            context: storageProvider.newTaskContext())
    }

    func process(_ urls: [URL], saveInto boardID: ObjectID, isSecurityScoped: Bool = true) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            let taskCounter = TaskCounter()
            let errorActor = ErrorActor()

            for url in urls {
                while await taskCounter.count >= maxTaskCount {
                    try await group.next()
                }

                await taskCounter.increment()

                group.addTask { [unowned self] in
                    processFile(url: url, saveInto: boardID, isSecurityScoped: isSecurityScoped) { error in
                        Task {
                            if let error = error {
                                await errorActor.setError(error)
                            }
                            await taskCounter.decrement()
                        }
                    }

                    if let error = await errorActor.error {
                        throw error
                    }
                }
            }

            while await 0 < taskCounter.count {
                try await group.next()
            }
        }
    }

    func process(_ itemProviders: [NSItemProvider], saveInto boardID: ObjectID? = nil, isSecurityScoped: Bool = true) async throws {
        let boardID = try unwrappedBoardID(of: boardID)

        try await withThrowingTaskGroup(of: Void.self) { group in
            let taskCounter = TaskCounter()
            let errorActor = ErrorActor()

            for provider in itemProviders {
                while await taskCounter.count >= maxTaskCount {
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
                        try await processLink(provider: provider, saveInto: boardID)
                        await taskCounter.decrement()
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        try await processText(provider: provider, saveInto: boardID)
                        await taskCounter.decrement()
                    } else {
                        processFile(provider: provider, saveInto: boardID, isSecurityScoped: isSecurityScoped) { error in
                            Task {
                                if let error = error {
                                    await errorActor.setError(error)
                                }
                                await taskCounter.decrement()
                            }
                        }
                    }

                    if let error = await errorActor.error {
                        throw error
                    }
                }
            }

            while await 0 < taskCounter.count {
                try await group.next()
            }
        }
    }

    func process(_ image: UIImage, saveInto boardID: ObjectID) async {
        // TODO: throwable
        let data = image.jpegData(compressionQuality: 1)

        let thumbnail = image.preparingThumbnail(of: CGSize(width: 400, height: 400))
        let thumbnailData = thumbnail?.jpegData(compressionQuality: 1)

        try? await storageProvider.addItem(
            displayType: .image,
            uti: UTType.jpeg.identifier,
            itemData: data,
            thumbnailData: thumbnailData,
            boardID: boardID)
    }

    func process(_ record: AudioRecord, saveInto boardID: ObjectID) throws {
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

            try? storageProvider.addItem(
                name: record.name,
                displayType: .audio,
                uti: uti,
                itemData: data,
                boardID: boardID)
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
    private func processLink(provider: NSItemProvider, saveInto boardID: ObjectID) async throws {
        guard let url = try await provider.loadObject(ofClass: URL.self) else {
            throw ImportError.invalidData
        }

        try await storageProvider.addItem(
            displayType: .link,
            uti: UTType.url.identifier,
            itemData: url.dataRepresentation,
            boardID: boardID)
    }

    private func processText(provider: NSItemProvider, saveInto boardID: ObjectID) async throws {
        if let string = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            try await processString(string, saveInto: boardID)
        } else if let string = try? await provider.loadObject(ofClass: String.self) {
            try await processString(string, saveInto: boardID)
        }
    }

    private func processString(_ string: String, saveInto boardID: ObjectID) async throws {
        if let url = string.validURL {
            try await storageProvider.addItem(
                displayType: .link,
                uti: UTType.url.identifier,
                itemData: url.dataRepresentation,
                boardID: boardID)
            return
        }

        try await storageProvider.addItem(
            displayType: .note,
            uti: UTType.utf8PlainText.identifier,
            note: string,
            boardID: boardID)
    }

    private func processFile(provider: NSItemProvider, saveInto boardID: ObjectID, isSecurityScoped: Bool, completion: @escaping (Error?) -> Void) {
        queue.addOperation {
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
                completion(ImportError.unsupportedType)
                return
            }

            print("#\(#function) start process file type:", typeIdentifier)

            provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { [unowned self] url, _, error in
                if let error = error {
                    completion(error)
                    return
                }

                guard let url = url else {
                    completion(ImportError.invalidURL)
                    return
                }

                let semaphore = DispatchSemaphore(value: 0)

                processFile(url: url, saveInto: boardID, isSecurityScoped: isSecurityScoped) { error in
                    if let error = error {
                        completion(error)
                    } else {
                        completion(nil)
                    }
                    semaphore.signal()
                }

                semaphore.wait()
            }
        }
    }

    private func processFile(url: URL, saveInto boardID: ObjectID, isSecurityScoped: Bool, completion: @escaping (Error?) -> Void) {
        queue.addOperation { [unowned self] in
            if isSecurityScoped {
                guard url.startAccessingSecurityScopedResource() else {
                    completion(ImportError.inaccessibleFile)
                    return
                }
            }

            defer { url.stopAccessingSecurityScopedResource() }

            let semaphore = DispatchSemaphore(value: 0)

            var readingError: NSError?

            fileCoordinator.coordinate(readingItemAt: url, error: &readingError) { url in
                guard
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey]),
                    let size = values.fileSize,
                    size <= 50_000_000,
                    let uti = values.contentType?.identifier,
                    let data = try? Data(contentsOf: url)
                else {
                    completion(ImportError.invalidData)
                    semaphore.signal()
                    return
                }

                let type = displayType(of: uti)
                let keepSourceName = type == .file
                let sourceName = (values.name as? NSString)?.deletingPathExtension

                thumbnailProvider.generateThumbnailData(url: url) { [unowned self] result in
                    defer { semaphore.signal() }

                    var thumbnailData: Data?
                    switch result {
                    case .success(let data):
                        thumbnailData = data
                    case .failure(let error):
                        print("#\(#function): Failed to generate thumbnail, \(error)")
                    }

                    do {
                        try storageProvider.addItem(
                            name: keepSourceName ? sourceName : nil,
                            displayType: type,
                            uti: uti,
                            itemData: data,
                            thumbnailData: thumbnailData,
                            boardID: boardID)
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            }

            if let readingError = readingError {
                completion(readingError)
                return
            }

            semaphore.wait()
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

private extension String {
    // ref: https://stackoverflow.com/questions/28079123/how-to-check-validity-of-url-in-swift/
    var validURL: URL? {
        guard
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
            let match = detector.firstMatch(in: self, range: NSRange(location: 0, length: self.utf16.count)),
            match.range.length == self.utf16.count
        else { return nil }

        return match.url
    }
}
