//
//  BoardSelectorViewController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/17.
//

import Combine
import UIKit

class BoardSelectorViewController: UIViewController {

    typealias Snapshot = NSDiffableDataSourceSnapshot<Int, Board>
    typealias DataSource = UICollectionViewDiffableDataSource<Int, Board>

    private let viewModel: BoardSelectorViewModel
    private var boards: [Board] = [] {
        didSet {
            applySnapshot()
        }
    }
    private var cancellable: AnyCancellable?

    private lazy var dataSource = createDataSource()

    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var titleLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.text = viewModel.scenario.title
        addBindings()
        configureCollectionView()
        configureSheetController()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        Task { await viewModel.fetchBoards() }
    }

    // MARK: - Initializers

    init?(coder: NSCoder, viewModel: BoardSelectorViewModel) {
        self.viewModel = viewModel
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    @IBAction func closeButtonTapped() {
        dismiss(animated: true)
    }

    // MARK: - Private

    private func applySnapshot() {
        var snapshot = Snapshot()
        snapshot.appendSections([0])
        snapshot.appendItems(boards)
        dataSource.apply(snapshot)
    }

    private func addBindings() {
        cancellable = viewModel.$boards
            .receive(on: DispatchQueue.main)
            .assign(to: \.boards, on: self)
    }

    private func configureSheetController() {
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.preferredCornerRadius = 30
        }
    }

    private func configureCollectionView() {
        collectionView.delegate = self
        collectionView.collectionViewLayout = createListLayout()
    }

    private func createListLayout() -> UICollectionViewLayout {
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .plain)
        listConfiguration.showsSeparators = false

        return UICollectionViewCompositionalLayout.list(using: listConfiguration)
    }

    private func createDataSource() -> DataSource {
        let cellRegistration = UICollectionView.CellRegistration(handler: cellRegistrationHandler)

        return DataSource(collectionView: collectionView) { collectionView, indexPath, board in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: board)
        }
    }

    private func cellRegistrationHandler(cell: UICollectionViewListCell, indexPath: IndexPath, board: Board) {
        var content = cell.defaultContentConfiguration()
        content.text = board.name
        content.textProperties.font = .systemFont(ofSize: 18, weight: .semibold)
        cell.contentConfiguration = content

        let backgroundView = UIView()
        backgroundView.backgroundColor = .label.withAlphaComponent(0.12)
        cell.selectedBackgroundView = backgroundView
    }
}

// MARK: - UICollectionViewDelegate

extension BoardSelectorViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        HUD.showProcessing()
        Task {
            do {
                let board = boards[indexPath.row]
                try await viewModel.moveItem(to: board.objectID)
                await MainActor.run {
                    dismiss(animated: true)
                    HUD.showSucceeded()
                }
            } catch {
                print("#\(#function): Failed to move item, \(error)")
                HUD.showFailed()
            }
        }
    }
}
