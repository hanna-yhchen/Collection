//
//  MainFlowController.swift
//  Collection
//
//  Created by Hanna Chen on 2022/11/26.
//

import LGSideMenuController
import UIKit

class MainFlowController: LGSideMenuController {

    private let storageProvider: StorageProvider
    private let rootNavigation: UINavigationController
    private let sideMenuViewController: SideMenuViewController

    private lazy var subscriptions = CancellableSet()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        configureRootNavigation()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if let leftView = leftView {
            let statusBarHeight = getStatusBarHeight()
            leftView.frame = CGRect(
                x: 0.0,
                y: statusBarHeight,
                width: leftView.bounds.width,
                height: view.bounds.height - statusBarHeight)
        }
    }

    // MARK: - Initializers

    init(storageProvider: StorageProvider) {
        self.storageProvider = storageProvider
        self.rootNavigation = UINavigationController()
        self.sideMenuViewController = SideMenuViewController(storageProvider: storageProvider)

        super.init(nibName: nil, bundle: nil)

        configureSideMenu()
        addObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private

    private func configureSideMenu() {
        rootViewController = rootNavigation
        leftViewController = sideMenuViewController

        leftViewPresentationStyle = .slideAside
        isLeftViewStatusBarBackgroundHidden = true

        rootViewCoverAlpha = 0.5
        rootViewCoverBlurEffect = UIBlurEffect(style: .regular)
        leftViewCoverBlurEffect = UIBlurEffect(style: .regular)
    }

    private func addObservers() {
        sideMenuViewController.destinationPublisher
            .sink { destination in
                self.transitionTo(destination)
            }
            .store(in: &subscriptions)
    }

    private func configureRootNavigation() {
        let standardAppearance = UINavigationBarAppearance()
        let arrowImage = UIImage(systemName: "arrow.left")
        standardAppearance.setBackIndicatorImage(arrowImage, transitionMaskImage: arrowImage)
        standardAppearance.configureWithDefaultBackground()
        rootNavigation.navigationBar.standardAppearance = standardAppearance

        let scrollEdgeAppearance = UINavigationBarAppearance(barAppearance: standardAppearance)
        scrollEdgeAppearance.configureWithTransparentBackground()
        rootNavigation.navigationBar.scrollEdgeAppearance = scrollEdgeAppearance

        rootNavigation.navigationBar.prefersLargeTitles = true

        let rootVC = createItemListVC(scope: .allItems)
        configureNavigationItem(for: rootVC)
        rootNavigation.setViewControllers([rootVC], animated: false)
    }

    @objc private func showSideMenu() {
        toggleLeftView(animated: true)
    }

    private func transitionTo(_ destination: SideMenuDestination) {
        var destinationVC: UIViewController

        switch destination {
        case .itemList(let scope):
            let itemListVC = createItemListVC(scope: scope)
            destinationVC = itemListVC
        case .boardList:
            let boardListVC = createBoardListVC()
            destinationVC = boardListVC
        }

        configureNavigationItem(for: destinationVC)

        rootNavigation.setViewControllers([destinationVC], animated: false)
        UIView.transition(
            with: rootNavigation.view,
            duration: leftViewAnimationDuration,
            options: [.transitionCrossDissolve],
            animations: nil)
        hideLeftView(animated: true)
    }

    private func createItemListVC(scope: ItemListViewModel.Scope) -> ItemListViewController {
        let menuProvider: OptionMenuProvider
        switch scope {
        case .allItems:
            menuProvider = OptionMenuProvider(boardID: nil)
        case .board(let boardID):
            menuProvider = OptionMenuProvider(boardID: boardID, storageProvider: storageProvider)
        }

        let viewModel = ItemListViewModel(
            scope: scope,
            storageProvider: storageProvider,
            menuProvider: menuProvider)

        let itemListVC = UIStoryboard.main.instantiateViewController(
            identifier: ItemListViewController.storyboardID
        ) { coder in
            ItemListViewController(
                coder: coder,
                viewModel: viewModel,
                delegate: self)
        }

        return itemListVC
    }

    private func createBoardListVC() -> BoardListViewController {
        let viewModel = BoardListViewModel(storageProvider: storageProvider)

        let boardListVC = UIStoryboard.main.instantiateViewController(
            identifier: String(describing: BoardListViewController.self)
        ) { coder in
            BoardListViewController(
                coder: coder,
                viewModel: viewModel,
                delegate: self)
        }

        return boardListVC
    }

    func showDeletionAlert(object: ManagedObject) {
        let alert = UIAlertController(
            title: Strings.Deletion.title(object.description),
            message: Strings.Deletion.reconfirmation(object.description),
            preferredStyle: UIDevice.current.userInterfaceIdiom == .phone ? .actionSheet : .alert)
        alert.addAction(UIAlertAction(title: Strings.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: Strings.Common.delete, style: .destructive) { [unowned self] _ in
            Task {
                do {
                    try await object.delete(context: storageProvider.persistentContainer.viewContext)
                    HUD.showSucceeded(Strings.Deletion.complete)
                } catch {
                    print("#\(#function): Failed to delete board, \(error)")
                    HUD.showFailed()
                }
            }
        })
        rootNavigation.present(alert, animated: true)
    }
}

// MARK: - BoardListViewControllerDelegate

extension MainFlowController: BoardListViewControllerDelegate {
    func navigateToItemList(boardID: ObjectID) {
        let itemListVC = createItemListVC(scope: .board(boardID))
        rootNavigation.pushViewController(itemListVC, animated: true)
    }

    func showNameEditorViewController(boardID: ObjectID) {
        let context = storageProvider.persistentContainer.viewContext
        guard let board = try? context.existingObject(with: boardID) as? Board else {
            HUD.showFailed(Strings.CommonError.missingData)
            return
        }

        let nameEditorVC = UIStoryboard.main
            .instantiateViewController(identifier: NameEditorViewController.storyboardID) { coder in
                NameEditorViewController(coder: coder, originalName: board.name)
            }
        nameEditorVC.modalPresentationStyle = .overCurrentContext
        #warning("Move update-related logic to name editor view model")
        nameEditorVC.cancellable = nameEditorVC.newNamePublisher
            .sink {[unowned self] newName in
                guard !newName.isEmpty else {
                    HUD.showFailed("The name of a board cannot be empty.")
                    return
                }

                Task {
                    do {
                        try await storageProvider.updateBoard(
                            boardID: boardID,
                            name: newName,
                            context: context)
                        await MainActor.run {
                            nameEditorVC.animateDismissSheet()
                        }
                    } catch {
                        print("#\(#function): Failed to rename item, \(error)")
                    }
                }
            }

        present(nameEditorVC, animated: false)
    }
}

// MARK: - ItemListViewControllerDelegate

extension MainFlowController: ItemListViewControllerDelegate {
    func showItemImportController(handler: ImportMethodHandling, boardID: ObjectID) {
        guard let itemImportVC = UIStoryboard.main.instantiateViewController(
            withIdentifier: ItemImportController.storyboardID
        ) as? ItemImportController else { return }

        itemImportVC.selectMethod
            .receive(on: DispatchQueue.main)
            .sink { method in
                handler.didSelectImportMethod(method)
            }
            .store(in: &handler.subscriptions)

        rootNavigation.present(itemImportVC, animated: true)
    }

    func showNameEditorViewController(itemID: ObjectID) {
        let context = storageProvider.persistentContainer.viewContext
        guard let item = try? context.existingObject(with: itemID) as? Item else {
            HUD.showFailed(Strings.CommonError.missingData)
            return
        }

        let nameEditorVC = UIStoryboard.main.instantiateViewController(
            identifier: NameEditorViewController.storyboardID
        ) { NameEditorViewController(coder: $0, originalName: item.name) }

        nameEditorVC.modalPresentationStyle = .overCurrentContext
        #warning("Move update-related logic to name editor view model")
        nameEditorVC.cancellable = nameEditorVC.newNamePublisher
            .sink { [unowned self] newName in
                Task {
                    do {
                        try await storageProvider.updateItem(
                            itemID: itemID,
                            name: newName,
                            context: context)
                        await MainActor.run {
                            nameEditorVC.animateDismissSheet()
                        }
                    } catch {
                        HUD.showFailed()
                        print("#\(#function): Failed to rename item, \(error)")
                    }
                }
            }

        rootNavigation.present(nameEditorVC, animated: false)
    }

    func showBoardSelectorViewController(scenario: BoardSelectorViewModel.Scenario) {
        let viewModel = BoardSelectorViewModel(storageProvider: storageProvider, scenario: scenario)
        let selectorVC = UIStoryboard.main.instantiateViewController(
            identifier: BoardSelectorViewController.storyboardID
        ) { BoardSelectorViewController(coder: $0, viewModel: viewModel) }

        rootNavigation.present(selectorVC, animated: true)
    }

    func showTagSelectorViewController(itemID: ObjectID) {
        let context = storageProvider.persistentContainer.viewContext
        guard
            let item = try? context.existingObject(with: itemID) as? Item,
            let board = item.board
        else {
            HUD.showFailed(Strings.CommonError.missingData)
            return
        }

        let viewModel = TagSelectorViewModel(
            storageProvider: storageProvider,
            itemID: itemID,
            boardID: board.objectID,
            context: context)
        let selectorVC = UIStoryboard.main.instantiateViewController(
            identifier: TagSelectorViewController.storyboardID
        ) { TagSelectorViewController(coder: $0, viewModel: viewModel) }

        let nav = UINavigationController(rootViewController: selectorVC)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.preferredCornerRadius = Constant.Layout.sheetCornerRadius
        }

        present(nav, animated: true)
    }
}

// MARK: - Helpers

extension MainFlowController {
    private func configureNavigationItem(for viewController: UIViewController) {
        viewController.navigationItem.backButtonDisplayMode = .minimal
        viewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal"),
            style: .plain,
            target: self,
            action: #selector(showSideMenu))
    }

    private func getStatusBarHeight() -> CGFloat {
        var statusBarHeight: CGFloat = 0
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first
        statusBarHeight = window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
        return statusBarHeight
    }
}
