//
//  ImportMethodHandling.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/11.
//

import UIKit
import PhotosUI

protocol ImportMethodHandling: UIViewController {
    var subscriptions: CancellableSet { get set }
    var itemManager: ItemManager { get }
    var boardID: ObjectID { get set }
    func didSelectImportMethod(_ method: ImportMethod)
}

extension ImportMethodHandling {
    func showNoteEditor() {
        let editorVC = UIStoryboard.main
            .instantiateViewController(identifier: NoteEditorViewController.storyboardID) { coder in
                let viewModel = NoteEditorViewModel(
                    itemManager: self.itemManager,
                    scenario: .create(boardID: self.boardID))
                return NoteEditorViewController(coder: coder, viewModel: viewModel)
            }

        if let sheet = editorVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.preferredCornerRadius = 30
        }

        present(editorVC, animated: true)
    }

    func showAudioRecorder() {
        let recorderVC = UIStoryboard.main
            .instantiateViewController(identifier: AudioRecorderController.storyboardID) { coder in
                return AudioRecorderController(coder: coder) {[unowned self] result in
                    HUD.showProcessing()

                    switch result {
                    case .success(let record):
                        Task {
                            do {
                                try await itemManager.process(record, saveInto: boardID)
                            } catch {
                                print("#\(#function): Failed to save new record, \(error)")
                            }
                            await dismissForSuccess()
                        }
                    case .failure(let error):
                        print("#\(#function): Failed to record new void memo, \(error)")
                        dismissForFailure()
                    }
                }
            }

        if let sheet = recorderVC.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.preferredCornerRadius = 30
        }

        present(recorderVC, animated: true, completion: nil)
    }

    func paste(_ itemProviders: [NSItemProvider]) {
        guard !itemProviders.isEmpty else { return }

        HUD.showImporting()

        Task {
            do {
                try await itemManager.process(itemProviders, saveInto: boardID, isSecurityScoped: false)
                HUD.showSucceeded()
            } catch {
                print("#\(#function): Failed to process input from pasteboard, \(error)")
                HUD.showFailed()
            }
        }
    }
}

extension ImportMethodHandling where Self: UIDocumentPickerDelegate {
    func showDocumentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.delegate = self
        picker.allowsMultipleSelection = true

        present(picker, animated: true)
    }

    func didPickDocument(_ controller: UIDocumentPickerViewController, urls: [URL]) {
        HUD.showImporting()

        Task {
            do {
                try await itemManager.process(urls, saveInto: boardID)
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                    HUD.showSucceeded()
                }
            } catch {
                print("#\(#function): Failed to process input from document picker, \(error)")
                HUD.showFailed()
            }
        }
    }
}

extension ImportMethodHandling where Self: PHPickerViewControllerDelegate {
    func showPhotoPicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 10
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self

        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }

        HUD.showImporting()

        Task {
            do {
                try await itemManager.process(results.map(\.itemProvider), saveInto: boardID, isSecurityScoped: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                    HUD.showSucceeded()
                }
            } catch {
                print("#\(#function): Failed to process input from photo picker, \(error)")
                HUD.showFailed()
            }
        }
    }
}

extension ImportMethodHandling where Self: UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    func openCamera() {
        let camera = UIImagePickerController.SourceType.camera
        guard
            UIImagePickerController.isSourceTypeAvailable(camera),
            UIImagePickerController.availableMediaTypes(for: camera) != nil
        else {
            HUD.showFailed()
            return
        }

        let picker = UIImagePickerController()
        picker.sourceType = camera
        picker.mediaTypes = [UTType.movie.identifier, UTType.image.identifier]
        picker.delegate = self

        present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        HUD.showProcessing()

        guard
            let typeIdentifier = info[.mediaType] as? String,
            let type = UTType(typeIdentifier)
        else {
            dismissForFailure()
            return
        }

        switch type {
        case .image:
            guard let image = info[.originalImage] as? UIImage else {
                dismissForFailure()
                return
            }

            Task {
                await itemManager.process(image, saveInto: boardID)
                await dismissForSuccess()
            }
        case .movie:
            guard let movieURL = info[.mediaURL] as? URL else {
                dismissForFailure()
                return
            }

            Task {
                do {
                    try await itemManager.process([movieURL], saveInto: boardID, isSecurityScoped: false)
                    await dismissForSuccess()
                } catch {
                    print("#\(#function): Failed to process movie captured from image picker, \(error)")
                    await dismissForFailure()
                }
            }
        default:
            dismissForFailure()
        }
    }
}
