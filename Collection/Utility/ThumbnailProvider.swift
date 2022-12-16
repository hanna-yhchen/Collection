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
    func generateThumbnailData(url: URL) async -> Result<Data, Error> {
        let request = await QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 400, height: 400),
            scale: UIScreen.main.scale,
            representationTypes: .thumbnail)

        do {
            let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)

            if let data = thumbnail.uiImage.pngData() {
                return .success(data)
            } else {
                return .failure(ThumbnailError.nilImageData)
            }
        } catch {
            return .failure(error)
        }
    }

    func generateThumbnailData(url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 400, height: 400),
            scale: UIScreen.main.scale,
            representationTypes: .thumbnail)

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let data = thumbnail?.uiImage.pngData() {
                completion(.success(data))
            } else {
                completion(.failure(ThumbnailError.nilImageData))
            }
        }
    }
}
