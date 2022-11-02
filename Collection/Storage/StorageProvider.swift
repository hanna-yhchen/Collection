//
//  StorageProvider.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import CoreData
import CloudKit

enum StorageActor: String {
    case mainApp
}

class StorageProvider {
    static let shared = StorageProvider(StorageActor.mainApp)

    // MARK: - Properties

    let actor: StorageActor

    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        /**
         Prepare containing folders for different persistence stores, because each store will have companion files.
         */
        let baseURL = NSPersistentContainer.defaultDirectoryURL()
        let storesFolder = baseURL.appendingPathComponent("CoreDataStores")
        let privateStoreFolder = storesFolder.appendingPathComponent("Private")
        let sharedStoreFolder = storesFolder.appendingPathComponent("Shared")

        let fileManager = FileManager.default

        for url in [privateStoreFolder, sharedStoreFolder] where !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            } catch {
                fatalError("#\(#function): Failed to create the store folder: \(error)")
            }
        }

        let container = NSPersistentCloudKitContainer(name: "Collection")

        /**
         Set up store descriptions associated with different CloudKit database.
         */
        guard let privateStoreDescription = container.persistentStoreDescriptions.first else {
            fatalError("#\(#function): Failed to retrieve a persistent store description.")
        }
        privateStoreDescription.url = privateStoreFolder.appendingPathComponent("Private.sqlite")
        privateStoreDescription.setOption(
            true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey)
        privateStoreDescription.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let privateStoreOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Constant.cloudKitContainerIdentifier)
        privateStoreOptions.databaseScope = .private

        privateStoreDescription.cloudKitContainerOptions = privateStoreOptions

        guard let sharedStoreDescription = privateStoreDescription.copy() as? NSPersistentStoreDescription else {
            fatalError("#\(#function): Copying the private store description returned an unexpected value.")
        }
        sharedStoreDescription.url = sharedStoreFolder.appendingPathComponent("Shared.sqlite")

        let sharedStoreOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Constant.cloudKitContainerIdentifier)
        sharedStoreOptions.databaseScope = .shared

        sharedStoreDescription.cloudKitContainerOptions = sharedStoreOptions

        /**
         Load the persistent stores.
         */
        container.persistentStoreDescriptions.append(sharedStoreDescription)
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("#\(#function): Failed to load persistent stores: \(error), \(error.userInfo)")
            }

            guard
                let cloudKitContainerOptions = storeDescription.cloudKitContainerOptions,
                let storeURL = storeDescription.url
            else {
                return
            }

            switch cloudKitContainerOptions.databaseScope {
            case .private:
                self._privatePersistentStore = container.persistentStoreCoordinator.persistentStore(for: storeURL)
            case .shared:
                self._sharedPersistentStore = container.persistentStoreCoordinator.persistentStore(for: storeURL)
            default:
                break
            }

            print(storeDescription)
        }

        /// Sync schema when needed during development
//        do {
//            try container.initializeCloudKitSchema()
//        } catch {
//            print("\(#function): initializeCloudKitSchema: \(error)")
//        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        /**
         Pin the viewContext to the current generation token and set it to keep itself up-to-date with local changes.
         */
        do {
            try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
            fatalError("#\(#function): Failed to pin viewContext to the current generation:\(error)")
        }

        fetchCurrentUser()

        return container
    }()

    // swiftlint:disable:next implicitly_unwrapped_optional
    private var _privatePersistentStore: NSPersistentStore!
    var privatePersistentStore: NSPersistentStore {
        return _privatePersistentStore
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    private var _sharedPersistentStore: NSPersistentStore!
    var sharedPersistentStore: NSPersistentStore {
        return _sharedPersistentStore
    }

    lazy var cloudKitContainer: CKContainer = {
        return CKContainer(identifier: Constant.cloudKitContainerIdentifier)
    }()

    var currentUserName: String?

    // MARK: - Initializer

    init(_ actor: StorageActor) {
        self.actor = actor
    }

    // MARK: - Methods

    func newTaskContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.transactionAuthor = actor.rawValue
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    // MARK: - Private

    private func fetchCurrentUser() {
        Task {
            do {
                let authStatus = try await cloudKitContainer.applicationPermissionStatus(for: .userDiscoverability)
                if authStatus == .granted {
                    let userRecordID = try await cloudKitContainer.userRecordID()
                    let userIdentity = try await cloudKitContainer.userIdentity(forUserRecordID: userRecordID)
                    if let nameComponents = userIdentity?.nameComponents {
                        let formatter = PersonNameComponentsFormatter()
                        let name = formatter.string(from: nameComponents)

                        self.currentUserName = name
                    }
                }
            } catch {
                print("#\(#function): Failed to fetch user, \(error)")
            }
        }
    }
}
