//
//  UserDefaults+Extension.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/3.
//

import Foundation

extension UserDefaults {
    @UserDefault(key: "username", defaultValue: "You")
    static var username: String
}
