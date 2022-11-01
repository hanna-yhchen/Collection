//
//  ThumbnailProvider.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/1.
//

import UIKit
import QuickLookThumbnailing

enum ThumbnailError: Error {
    case nilImageData
}

struct ThumbnailProvider {
    func generateThumbnailData(url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 400, height: 400),
            scale: UIScreen.main.scale,
            representationTypes: .thumbnail)

        Task {
            do {
                let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)

                if let data = thumbnail.uiImage.pngData() {
                    completion(.success(data))
                } else {
                    completion(.failure(ThumbnailError.nilImageData))
                }
            } catch {
                print("#\(#function): Failed to generate thumbnail, \(error)")
                completion(.failure(error))
            }
        }
    }
}
