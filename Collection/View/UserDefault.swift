//
//  UserDefault.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/3.
//

import Foundation

@propertyWrapper
struct UserDefault<Value> {
    let key: String
    let defaultValue: Value
    let userDefaults = UserDefaults.standard

    var wrappedValue: Value {
        get {
            userDefaults.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            userDefaults.set(newValue, forKey: key)
        }
    }
}
