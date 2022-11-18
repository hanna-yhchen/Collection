//
//  TagSelectorViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/18.
//

import UIKit

class TagSelectorViewController: UIViewController {

    @IBOutlet var collectionView: UICollectionView!

    private let viewModel: TagSelectorViewModel

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureCollectionView()
        navigationController?.isNavigationBarHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        viewModel.fetchTags()
    }

    init?(coder: NSCoder, viewModel: TagSelectorViewModel) {
        self.viewModel = viewModel
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    private func configureCollectionView() {
        collectionView.collectionViewLayout = createListLayout()
        collectionView.allowsMultipleSelection = true
        collectionView.delegate = self

        viewModel.configureDataSource(for: collectionView)
    }

    private func createListLayout() -> UICollectionViewLayout {
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .plain)
        listConfiguration.showsSeparators = false

        return UICollectionViewCompositionalLayout.list(using: listConfiguration)
    }

    // MARK: - Actions

    @IBAction func plusButtonTapped() {
        let newTagVC = UIStoryboard.main.instantiateViewController(
            withIdentifier: NewTagViewController.storyboardID)

        navigationController?.pushViewController(newTagVC, animated: true)
    }

    @IBAction func closeButtonTapped() {
        navigationController?.dismiss(animated: true)
    }
}

extension TagSelectorViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        viewModel.toggleTagAt(indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        viewModel.toggleTagAt(indexPath)
    }
}
