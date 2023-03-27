//
//  ItemImportController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/14.
//

import Combine
import UIKit

class ItemImportController: UIViewController {

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var collectionView: UICollectionView!

    lazy var selectMethod = PassthroughSubject<ImportMethod, Never>()
    @Published var selectedMethod: ImportMethod?

    lazy var sheetHeight: CGFloat = titleBarHeight
        + flowLayout.itemSize.height * 2
        + spacing * 2

    private let titleBarHeight: CGFloat = 46
    private let spacing: CGFloat = 16

    private lazy var flowLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()

        layout.minimumLineSpacing = spacing
        layout.minimumInteritemSpacing = spacing

        let itemsPerRow: CGFloat = 4
        var fullWidth = view.bounds.width
        if view.traitCollection.horizontalSizeClass == .regular {
            fullWidth = 300
        }
        let availableWidth = fullWidth - ((itemsPerRow + 1) * 20)
        let widthPerItem = (availableWidth / itemsPerRow).rounded(.down)
        layout.itemSize = CGSize(width: widthPerItem, height: widthPerItem + 30)

        return layout
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.text = Strings.ItemImport.title
        configureCollectionView()
        configureSheetPresentation()
    }

    // MARK: - Private

    private func configureCollectionView() {
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        collectionView.register(
            UINib(nibName: ImportMethodCell.identifier, bundle: nil),
            forCellWithReuseIdentifier: ImportMethodCell.identifier)
        collectionView.collectionViewLayout = flowLayout
    }

    private func configureSheetPresentation() {
        if let sheet = sheetPresentationController {
            if #available(iOS 16.0, *) {
                sheet.detents = [.custom { [unowned self] _ in self.sheetHeight }]
            } else {
                sheet.detents = [.medium()]
            }
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.preferredCornerRadius = Constant.Layout.sheetCornerRadius
        }

        modalPresentationStyle = .formSheet
        preferredContentSize = CGSize(width: 300, height: 400)
    }
}

// MARK: - UICollectionViewDataSource

extension ItemImportController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        ImportMethod.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ImportMethodCell.identifier,
            for: indexPath) as? ImportMethodCell
        else { fatalError("Failed to dequeue ImportMethodCell") }

        if let method = ImportMethod(rawValue: indexPath.row) {
            cell.configure(for: method)
        }

        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension ItemImportController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let method = ImportMethod(rawValue: indexPath.row) {
            dismiss(animated: true) {
                self.selectMethod.send(method)
            }
        }
    }
}
