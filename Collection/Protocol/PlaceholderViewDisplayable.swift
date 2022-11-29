//
//  PlaceholderViewDisplayable.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/29.
//

import UIKit

protocol PlaceholderViewDisplayable: UIViewController {
    var placeholderView: HintPlaceholderView? { get set }
}

extension PlaceholderViewDisplayable {
    func showPlaceholderView() {
        DispatchQueue.main.async {[self] in
            let placeholderView = HintPlaceholderView()
            view.addSubview(placeholderView)
            placeholderView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                placeholderView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                placeholderView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            self.placeholderView = placeholderView
            view.layoutIfNeeded()
        }
    }

    func removePlaceholderView() {
        DispatchQueue.main.async {[self] in
            placeholderView?.removeFromSuperview()
            placeholderView = nil
            view.layoutIfNeeded()
        }
    }
}
