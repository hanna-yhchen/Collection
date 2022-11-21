//
//  AppDelegate.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/28.
//

import IQKeyboardManagerSwift
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        configureKeyboardManager()
        prepareForFirstLaunch()

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

extension AppDelegate {
    private func configureKeyboardManager() {
        let manager = IQKeyboardManager.shared
        manager.enable = true
        manager.shouldShowToolbarPlaceholder = false
        manager.shouldResignOnTouchOutside = true
        manager.disabledToolbarClasses = [NameEditorViewController.self]
        manager.disabledTouchResignedClasses = [NameEditorViewController.self]
        manager.disabledDistanceHandlingClasses = [NoteEditorViewController.self]
    }

    private func prepareForFirstLaunch() {
        if UserDefaults.isFirstLaunch {
            let viewContext = StorageProvider.shared.persistentContainer.viewContext
            StorageProvider.shared.addBoard(name: "Inbox", context: viewContext)

            let fetchRequest = Board.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "%K = %@", #keyPath(Board.name), "Inbox" as String)
            fetchRequest.fetchLimit = 1

            if let inboxBoard = try? viewContext.fetch(fetchRequest).first {
                UserDefaults.defaultBoardURL = inboxBoard.objectID.uriRepresentation().absoluteString
            }

            // FIXME: (concurrency issue) there will be duplicate inbox board if user ever installed this app and sync with iCloud before

            UserDefaults.isFirstLaunch = false
        }
    }
}
