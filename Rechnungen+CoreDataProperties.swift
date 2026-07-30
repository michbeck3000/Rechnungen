//
//  Rechnungen+CoreDataProperties.swift
//  Rechnungen
//
//  Created by michbeck on 21.04.25.
//
//

import Foundation
import CoreData


extension Rechnungen {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Rechnungen> {
        return NSFetchRequest<Rechnungen>(entityName: "Rechnungen")
    }

    @NSManaged public var bild: Data?
    @NSManaged public var datum: Date?
    @NSManaged public var faelligkeit: Date?
    @NSManaged public var iban: String?
    @NSManaged public var name: String?
    @NSManaged public var nummer: String?
    @NSManaged public var status: String?
    @NSManaged public var pdf: Data?
    @NSManaged public var summe: NSDecimalNumber?

}

extension Rechnungen : Identifiable {

}
