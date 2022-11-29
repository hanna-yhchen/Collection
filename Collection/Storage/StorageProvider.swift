//
//  StorageProvider.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import CoreData
import CloudKit

enum StorageActor: String, CaseIterable {
    case mainApp, shareExtension
}

enum AppIdentifier {
    static let coreDataModel = "Collection"
    static let cloudKitContainer = "iCloud.com.yhchen.CollectionOfInspiration"
    static let appGroup = "group.com.yhchen.Collection"
}

enum UserInfoKey {
    static let storeUUID = "storeUUID"
    static let transactions = "transactions"
}

class StorageProvider {
    static let shared = StorageProvider()

    // MARK: - Properties

    lazy var actor: StorageActor = {
        #if MainApp
        return .mainApp
        #elseif ShareExtension
        return .shareExtension
        #endif
    }()
    let persistentContainer: NSPersistentCloudKitContainer
    var historyManager: StorageHistoryManager?

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

    lazy var cloudKitContainer = CKContainer(identifier: AppIdentifier.cloudKitContainer)

    // MARK: - Initializer

    init() {
        // TODO: use custom flags to specify current target
        self.persistentContainer = NSPersistentCloudKitContainer(name: AppIdentifier.coreDataModel)
        // TODO: tackle the situation when user turn off iCloud sync
        configurePersistentContainer()
//        initializeCloudKitSchema()

        if actor == .mainApp {
            self.historyManager = StorageHistoryManager(storageProvider: self, actor: actor)
//            fetchCurrentUser()
        }
    }

    // MARK: - Methods

    func newTaskContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.transactionAuthor = actor.rawValue
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

//    func fetchCurrentUser() {
//        Task {
//            do {
//                let authStatus = try await cloudKitContainer.requestApplicationPermission(.userDiscoverability)
//                if authStatus == .granted {
//                    let userRecordID = try await cloudKitContainer.userRecordID()
//                    let userIdentity = try await cloudKitContainer.userIdentity(forUserRecordID: userRecordID)
//                    UserDefaults.username = userIdentity?.nameComponents?.formatted() ?? "You"
//                }
//            } catch {
//                print("#\(#function): Failed to fetch user, \(error)")
//            }
//        }
//    }

    func mergeTransactions(_ transactions: [NSPersistentHistoryTransaction], to context: NSManagedObjectContext) {
        context.perform {
            transactions.forEach { context.mergeChanges(fromContextDidSave: $0.objectIDNotification()) }
        }
    }

    // MARK: - Private

    private func configurePersistentContainer() {
        persistentContainer.persistentStoreDescriptions = createStoreDescriptions()

        persistentContainer.loadPersistentStores {[unowned self] storeDescription, error in
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
                _privatePersistentStore = persistentContainer.persistentStoreCoordinator.persistentStore(for: storeURL)
            case .shared:
                _sharedPersistentStore = persistentContainer.persistentStoreCoordinator.persistentStore(for: storeURL)
            default:
                break
            }

            print("#\(#function): Load persistent store", storeDescription)
        }

        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        /// Pin the viewContext to the current generation token (snapshot) for UI stability.
        do {
            try persistentContainer.viewContext.setQueryGenerationFrom(.current)
        } catch {
            fatalError("#\(#function): Failed to pin viewContext to the current generation:\(error)")
        }
    }

    private func createStoreDescriptions() -> [NSPersistentStoreDescription] {
        let (privateFolderURL, sharedFolderURL) = prepareStoreFolders()

        guard let privateStoreDescription = persistentContainer.persistentStoreDescriptions.first else {
            fatalError("#\(#function): Failed to retrieve a persistent store description.")
        }
        privateStoreDescription.url = privateFolderURL.appendingPathComponent("Private.sqlite")

        /// Enable history tracking in main app.
        if actor == .mainApp {
            privateStoreDescription.setOption(
                true as NSNumber,
                forKey: NSPersistentHistoryTrackingKey)
            privateStoreDescription.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        let privateStoreOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: AppIdentifier.cloudKitContainer)
        privateStoreOptions.databaseScope = .private
        privateStoreDescription.cloudKitContainerOptions = privateStoreOptions

        guard let sharedStoreDescription = privateStoreDescription.copy() as? NSPersistentStoreDescription else {
            fatalError("#\(#function): Copying the private store description returned an unexpected value.")
        }
        sharedStoreDescription.url = sharedFolderURL.appendingPathComponent("Shared.sqlite")

        let sharedStoreOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: AppIdentifier.cloudKitContainer)
        sharedStoreOptions.databaseScope = .shared
        sharedStoreDescription.cloudKitContainerOptions = sharedStoreOptions

        return [privateStoreDescription, sharedStoreDescription]
    }
}

// MARK: - Helpers

extension StorageProvider {
    private func prepareStoreFolders() -> (privateFolderURL: URL, sharedFolderURL: URL) {
        // swiftlint:disable:next force_unwrapping
        let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifier.appGroup)!
        let storesFolder = baseURL.appendingPathComponent("CoreDataStores")
        let privateStoreFolder = storesFolder.appendingPathComponent("Private")
        let sharedStoreFolder = storesFolder.appendingPathComponent("Shared")

        let fileManager = FileManager.default
        [privateStoreFolder, sharedStoreFolder]
            .filter { !fileManager.fileExists(atPath: $0.path) }
            .forEach { url in
                do {
                    try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    fatalError("#\(#function): Failed to create the store folder: \(error)")
                }
            }

        return (privateStoreFolder, sharedStoreFolder)
    }

    /// Sync schema when needed during development
    private func initializeCloudKitSchema() {
        do {
            try persistentContainer.initializeCloudKitSchema()
        } catch {
            print("\(#function): initializeCloudKitSchema: \(error)")
        }
    }
}
