//
//  UTType+Extension.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/10.
//

import Foundation
import UniformTypeIdentifiers

// swiftlint:disable force_unwrapping

extension UTType {
    static var heifStandard: UTType {
        UTType("public.heif-standard")!
    }

    static var livePhotoBundle: UTType {
        UTType("com.apple.live-photo-bundle")!
    }
}
