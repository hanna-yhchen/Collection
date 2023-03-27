//
//  ProgressHUDWrapper.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/21.
//

import ProgressHUD

enum HUD {
    static func show() {
        ProgressHUD.show()
    }

    static func showProcessing() {
        ProgressHUD.show(Strings.Hud.processing)
    }

    static func showImporting() {
        ProgressHUD.show(Strings.Hud.importing)
    }

    static func showSucceeded(_ message: String? = nil) {
        ProgressHUD.showSucceed(message)
    }

    static func showFailed(_ message: String? = nil) {
        ProgressHUD.showFailed(message)
    }

    static func dismiss() {
        ProgressHUD.dismiss()
    }
}
