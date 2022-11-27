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

//        rootViewLayerShadowRadius = 0
//        leftViewLayerShadowRadius = 0
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

        let rootVC = UIStoryboard.main
            .instantiateViewController(identifier: ItemListViewController.storyboardID) { coder in
                ItemListViewController(coder: coder, scope: .allItems, storageProvider: self.storageProvider)
            }
        configureNavigationItem(for: rootVC)
        rootNavigation.setViewControllers([rootVC], animated: false)
    }

    // MARK: - Actions

    @objc private func showSideMenu() {
        toggleLeftView(animated: true)
    }

    // MARK: - Navigations

    private func transitionTo(_ destination: SideMenuDestination) {
        var destinationVC: UIViewController

        switch destination {
        case .itemList(let scope):
            let itemListVC = UIStoryboard.main
                .instantiateViewController(identifier: ItemListViewController.storyboardID) { coder in
                    ItemListViewController(coder: coder, scope: scope, storageProvider: self.storageProvider)
                }
            destinationVC = itemListVC
        case .boardList:
            let boardListVC = UIStoryboard.main
                .instantiateViewController(identifier: String(describing: BoardListViewController.self)) { coder in
                    BoardListViewController(coder: coder, storageProvider: self.storageProvider)
                }
            destinationVC = boardListVC
        case .tagList:
            // TODO: instantiate tag list vc
            destinationVC = UIViewController()
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
}

// MARK: - Helper

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
