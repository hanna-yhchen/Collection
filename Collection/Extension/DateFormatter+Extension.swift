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
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

extension DateComponentsFormatter {
    static let audioDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.allowsFractionalUnits = true
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter
    }()
}
