//
//  UIViewController+Extension.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/25.
//

import UIKit

// MARK: - HUD Helper

extension UIViewController {
    func dismissForFailure() {
        guard presentedViewController != nil else { return }

        DispatchQueue.main.async {
            self.dismiss(animated: true)
            HUD.showFailed()
        }
    }

    func dismissForSuccess() {
        guard presentedViewController != nil else { return }

        DispatchQueue.main.async {
            self.dismiss(animated: true)
            HUD.showSucceeded()
        }
    }
}
