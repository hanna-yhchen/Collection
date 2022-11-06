//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Hanna Chen on 2022/11/5.
//
/*
 Build files:
 StorageProvider, StorageProvider+Item, StorageHistoryManage, UserDefault, UserDefaults+Extension, Collection(Core Data Model), DateFormatter+Extensions, ThumbnailProvider, ItemImportManager
 */

import CoreData
import UIKit
import Social

enum ShareExtensionError: Error {
    case unfoundDefaultBoard
    case failedToRetrieveAttachments
}

class ShareViewController: SLComposeServiceViewController {

    lazy var importManager: ItemImportManager? = {
        let storageProvider = StorageProvider.shared

        guard
            let url = URL(string: UserDefaults.defaultBoardURL),
            let boardID = storageProvider.persistentContainer.persistentStoreCoordinator
                .managedObjectID(forURIRepresentation: url)
        else {
            extensionContext?.cancelRequest(withError: ShareExtensionError.unfoundDefaultBoard)
            return nil
        }

        return ItemImportManager(storageProvider: storageProvider, boardID: boardID)
    }()

    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        return true
    }

    override func didSelectPost() {
        guard let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?.first?.attachments else {
            extensionContext?.cancelRequest(withError: ShareExtensionError.failedToRetrieveAttachments)
            return
        }

        importManager?.process(attachments) { error in
            if let error = error {
                print(error)
            }
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }
}
