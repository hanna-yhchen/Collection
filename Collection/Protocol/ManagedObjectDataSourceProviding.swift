//
//  ManagedObjectDataSourceProviding.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/8.
//

import UIKit

protocol ManagedObjectDataSourceProviding: AnyObject {
    associatedtype Object: ManagedObject

    var dataSource: ManagedObjectDataSource? { get set }
    func configureDataSource(
        for collectionView: UICollectionView,
        cellProvider: @escaping (IndexPath, Object) -> UICollectionViewCell?
    )
}

extension ManagedObjectDataSourceProviding {
    func objectID(for indexPath: IndexPath) -> ObjectID? {
        guard let dataSource = dataSource else { return nil }
        return dataSource.itemIdentifier(for: indexPath)
    }

    func indexPath(for objectID: ObjectID) -> IndexPath? {
        guard let dataSource = dataSource else { return nil }
        return dataSource.indexPath(for: objectID)
    }
}
