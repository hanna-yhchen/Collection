//
//  UserDefaults+Extension.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/3.
//

import Foundation

extension UserDefaults {
    static let shared = UserDefaults(suiteName: AppIdentifier.appGroup)! // swiftlint:disable:this force_unwrapping

    @UserDefault(key: "username", defaultValue: "You")
    static var username: String

    @UserDefault(key: "defaultBoardName", defaultValue: "Inbox", userDefaults: .shared)
    static var defaultBoardName: String

    @UserDefault(
        key: "historyTracking.lastTimestamp." + StorageProvider.shared.actor.rawValue,
        defaultValue: .distantPast,
        userDefaults: .shared)
    static var historyTimestamp: Date
}
