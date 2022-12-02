//
//  StorageHistoryManager.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/4.
//

import Combine
import CoreData

final class StorageHistoryManager {
    // MARK: - Properties
    let storeDidChangePublisher = PassthroughSubject<[NSPersistentHistoryTransaction], Never>()

    private let storageProvider: StorageProvider
    private let actor: StorageActor

    private lazy var queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private lazy var context = storageProvider.newTaskContext()

    private var subscriptions: Set<AnyCancellable> = []

    // MARK: - Initializer

    init(storageProvider: StorageProvider, actor: StorageActor) {
        self.storageProvider = storageProvider
        self.actor = actor

        addObservers()
    }

    // MARK: - Private

    private func addObservers() {
        NotificationCenter.default.publisher(
            for: .NSPersistentStoreRemoteChange,
            object: storageProvider.persistentContainer.persistentStoreCoordinator
        )
        .subscribe(on: queue)
        .sink { notification in
            self.processRemoteChange(notification)
        }
        .store(in: &subscriptions)
    }

    private func processRemoteChange(_ notification: Notification) {
        let privateStore = storageProvider.privatePersistentStore
        let sharedStore = storageProvider.sharedPersistentStore

        guard
            let storeUUID = notification.userInfo?[NSStoreUUIDKey] as? String,
            [privateStore.identifier, sharedStore.identifier].contains(storeUUID)
        else {
            print("\(#function): Ignore a store remote Change notification because of no valid storeUUID.")
            return
        }

        /// Fetch all transactions made by other authors
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: UserDefaults.historyTimestamp)
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Transaction")
        fetchRequest.predicate = NSPredicate(
            format: "%K != %@",
            #keyPath(NSPersistentHistoryTransaction.author),
            actor.rawValue)
        request.fetchRequest = fetchRequest

        if privateStore.identifier == storeUUID {
            request.affectedStores = [privateStore]
        } else if sharedStore.identifier == storeUUID {
            request.affectedStores = [sharedStore]
        }

        let result = (try? context.execute(request)) as? NSPersistentHistoryResult
        guard let transactions = result?.result as? [NSPersistentHistoryTransaction] else {
            return
        }

        if !transactions.isEmpty {
            storeDidChangePublisher.send(transactions)
        }

        if let lastTimestamp = transactions.last?.timestamp {
            UserDefaults.historyTimestamp = lastTimestamp
        }

        // TODO: delete merged history before 7 days ago
        // TODO: deduplicate objects if current user is the author
    }
}
