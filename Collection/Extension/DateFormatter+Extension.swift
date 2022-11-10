//
//  DateFormatter+Extensions.swift
//  Collection
//
//  Created by Hanna Chen on 2022/10/31.
//

import Foundation

extension DateFormatter {
    static let hyphenatedDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
