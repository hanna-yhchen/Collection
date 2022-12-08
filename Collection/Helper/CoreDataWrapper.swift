//
//  CoreDataWrapper.swift
//  Collection
//
//  Created by Hanna Chen on 2022/12/7.
//

import CoreData
import UIKit

typealias ObjectID = NSManagedObjectID
typealias ManagedObject = NSManagedObject
typealias ManagedObjectSnapshot = NSDiffableDataSourceSnapshot<Int, ObjectID>
typealias ManagedObjectDataSource = UICollectionViewDiffableDataSource<Int, ObjectID>
