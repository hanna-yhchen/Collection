//
//  UITextView+Extension.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/9.
//

import Combine
import UIKit

extension UITextView {
    var textPublisher: AnyPublisher<String, Never> {
        NotificationCenter.default
            .publisher(for: UITextView.textDidChangeNotification, object: self)
            .compactMap { ($0.object as? UITextView)?.text }
            .eraseToAnyPublisher()
    }
}
