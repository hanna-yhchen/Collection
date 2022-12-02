//
//  TagSelectorViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/18.
//

import UIKit

class TagSelectorViewController: UIViewController {

    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var editButton: UIButton!

    private let viewModel: TagSelectorViewModel
    private lazy var subscriptions = CancellableSet()

    @Published private var isEditingTags = false {
        didSet {
            collectionView.isEditing = isEditingTags
            editButton.setNeedsUpdateConfiguration()
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        configureCollectionView()
        addBindings()
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

    private func configureHierarchy() {
        navigationController?.isNavigationBarHidden = true
        titleLabel.text = "Tags in \(viewModel.boardName())"

        editButton.configurationUpdateHandler = { [unowned self] button in
            var config = button.configuration
            config?.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 0)
            config?.titleAlignment = .trailing
            config?.attributedTitle = AttributedString(
                isEditingTags ? "Done" : "Edit",
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)])
            )
            config?.baseForegroundColor = .systemIndigo
            button.configuration = config
        }
    }

    private func addBindings() {
        $isEditingTags
            .assign(to: \.isEditing, on: viewModel)
            .store(in: &subscriptions)
        viewModel.createTagFooterTap
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] in
                showTagEditor(viewModel: viewModel.newTagViewModel())
            }
            .store(in: &subscriptions)
    }

    private func configureCollectionView() {
        collectionView.collectionViewLayout = createListLayout()
        collectionView.allowsMultipleSelection = true
        collectionView.delegate = self
        collectionView.allowsMultipleSelectionDuringEditing = false

        viewModel.configureDataSource(for: collectionView)
    }

    private func createListLayout() -> UICollectionViewLayout {
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .plain)
        listConfiguration.showsSeparators = false
        listConfiguration.footerMode = .supplementary

        return UICollectionViewCompositionalLayout.list(using: listConfiguration)
    }

    func showTagEditor(viewModel: TagEditorViewModel) {
        isEditingTags = false

        let newTagVC = UIStoryboard.main
            .instantiateViewController(identifier: TagEditorViewController.storyboardID) { coder in
                TagEditorViewController(coder: coder, viewModel: viewModel)
            }

        navigationController?.pushViewController(newTagVC, animated: true)
    }

    // MARK: - Actions

    @IBAction func editButtonTapped() {
        isEditingTags.toggle()
    }

    @IBAction func closeButtonTapped() {
        navigationController?.dismiss(animated: true)
    }
}

// MARK: - UICollectionViewDelegate

extension TagSelectorViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isEditingTags {
            collectionView.deselectItem(at: indexPath, animated: false)
            showTagEditor(viewModel: viewModel.editTagViewModel(at: indexPath))
        } else {
            viewModel.toggleTag(at: indexPath)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard !isEditingTags else { return }
        viewModel.toggleTag(at: indexPath)
    }
}
