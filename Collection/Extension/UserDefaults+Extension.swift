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

    @UserDefault(key: "defaultBoardURL", defaultValue: "", userDefaults: .shared)
    static var defaultBoardURL: String

    @UserDefault(
        key: "historyTracking.lastTimestamp." + StorageProvider.shared.actor.rawValue,
        defaultValue: .distantPast,
        userDefaults: .shared)
    static var historyTimestamp: Date

    @UserDefault(key: "isFirstLaunch", defaultValue: true)
    static var isFirstLaunch: Bool

    @UserDefault(key: "linkMetadataCache", defaultValue: [:])
    static var linkMetadataCache: [String: Data]
}
