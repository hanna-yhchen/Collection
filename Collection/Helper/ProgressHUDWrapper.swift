//
//  ProgressHUDWrapper.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/21.
//

import ProgressHUD

enum HUD {
    static func show() {
        ProgressHUD.animationType = .circleRotateChase
        ProgressHUD.show()
    }

    static func showProgressing() {
        ProgressHUD.animationType = .circleRotateChase
        ProgressHUD.show("Progressing")
    }

    static func showImporting() {
        ProgressHUD.animationType = .circleRotateChase
        ProgressHUD.show("Importing")
    }

    static func showSucceeded() {
        ProgressHUD.showSucceed()
    }

    static func showFailed(message: String? = nil) {
        ProgressHUD.showFailed(message)
    }

    static func dismiss() {
        ProgressHUD.dismiss()
    }
}
