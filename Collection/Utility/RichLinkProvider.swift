//
//  RichLinkProvider.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/13.
//

import Combine
import LinkPresentation

class RichLinkProvider {
    static let shared = RichLinkProvider()

    typealias RichLink = (title: String?, host: String?, image: UIImage?)
    typealias RichLinkResult = Result<RichLink, Error>

    enum RichLinkError: Error {
        case foundNilMetadata
    }

    // MARK: - Initializer

    private init() {}

    // MARK: - Methods

    func fetchMetadata(for url: URL) -> Future<RichLink, Error> {
        Future {[unowned self] promise in
            if let metadata = retrieveMetadata(for: url.absoluteString) {
                loadLPLinkMetadata(metadata) { richLink in
                    promise(.success(richLink))
                }
                return
            }

            let metadataProvider = LPMetadataProvider()
            metadataProvider.startFetchingMetadata(for: url) {[unowned self] metadata, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }

                if let metadata = metadata {
                    cache(metadata: metadata)
                    loadLPLinkMetadata(metadata) { richLink in
                        promise(.success(richLink))
                    }
                } else {
                    promise(.failure(RichLinkError.foundNilMetadata))
                }
            }
        }
    }

    // MARK: - Private

    private func loadLPLinkMetadata(_ metadata: LPLinkMetadata, completion: @escaping (RichLink) -> Void) {
        let host = metadata.url?.host
        let conciseHost = host?.replacingOccurrences(of: "^www.", with: "", options: .regularExpression)

        if let imageProvider = metadata.imageProvider {
            imageProvider.loadObject(ofClass: UIImage.self) { image, error in
                if let error = error {
                    print("#\(#function): Failed to load image data from LPLinkMetadata, \(error)")
                }
                completion((metadata.title, conciseHost ?? host, (image as? UIImage)))
            }
        } else {
            completion((metadata.title, conciseHost ?? host, nil))
        }
    }

    private func cache(metadata: LPLinkMetadata) {
        guard
            let urlString = metadata.originalURL?.absoluteString,
            retrieveMetadata(for: urlString) == nil
        else { return }

        do {
            #warning("Replace with more solid cache solution")
            var cache = UserDefaults.linkMetadataCache
            while cache.count > 10 {
                cache.removeValue(forKey: cache.randomElement()!.key) // swiftlint:disable:this force_unwrapping
            }

            let data = try NSKeyedArchiver.archivedData(withRootObject: metadata, requiringSecureCoding: true)
            cache[urlString] = data
            UserDefaults.linkMetadataCache = cache
        } catch {
            print("#\(#function): Failed to cache LPLinkMetadata, \(error)")
        }
    }

    private func retrieveMetadata(for urlString: String) -> LPLinkMetadata? {
        guard let cachedData = UserDefaults.linkMetadataCache[urlString] else { return nil}

        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: cachedData)
        } catch {
            print("Failed to unarchive metadata with error \(error as NSError)")
            return nil
        }
    }
}
