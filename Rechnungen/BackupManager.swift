import Foundation
import CoreData
import UIKit

class BackupManager {
    static let shared = BackupManager()
    
    private let persistenceController = PersistenceController.shared
    
    private init() {}
    
    // MARK: - Backup Export
    
    func exportBackup() throws -> URL {
        let backupData = try createBackupData()
        let backupURL = try saveBackupToFile(backupData)
        return backupURL
    }
    
    private func createBackupData() throws -> [String: Any] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<Rechnungen> = Rechnungen.fetchRequest()
        
        let rechnungen = try context.fetch(fetchRequest)
        
        var backupArray: [[String: Any]] = []
        
        for rechnung in rechnungen {
            var rechnungDict: [String: Any] = [:]
            
            // Textdaten
            rechnungDict["name"] = rechnung.name ?? ""
            rechnungDict["nummer"] = rechnung.nummer ?? ""
            rechnungDict["status"] = rechnung.status ?? ""
            rechnungDict["iban"] = rechnung.iban ?? ""
            
            // Datumswerte
            if let datum = rechnung.datum {
                rechnungDict["datum"] = ISO8601DateFormatter().string(from: datum)
            }
            
            if let faelligkeit = rechnung.faelligkeit {
                rechnungDict["faelligkeit"] = ISO8601DateFormatter().string(from: faelligkeit)
            }
            
            // Betrag
            if let summe = rechnung.summe {
                rechnungDict["summe"] = summe.stringValue
            }
            
            // Bilddaten (Base64-kodiert)
            if let bildData = rechnung.bild {
                rechnungDict["bild"] = bildData.base64EncodedString()
            }
            
            // PDF-Daten (Base64-kodiert)
            if let pdfData = rechnung.pdf {
                rechnungDict["pdf"] = pdfData.base64EncodedString()
            }
            
            backupArray.append(rechnungDict)
        }
        
        let backupDict: [String: Any] = [
            "version": "1.0",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "rechnungen": backupArray
        ]
        
        return backupDict
    }
    
    private func saveBackupToFile(_ backupData: [String: Any]) throws -> URL {
        let jsonData = try JSONSerialization.data(withJSONObject: backupData, options: .prettyPrinted)
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "Rechnungen_Backup_\(dateFormatter.string(from: Date())).json"
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        try jsonData.write(to: fileURL)
        return fileURL
    }
    
    // MARK: - Backup Import
    
    func importBackup(from url: URL) throws -> ImportResult {
        // Sicheren Zugriff auf die Datei gewährleisten
        guard url.startAccessingSecurityScopedResource() else {
            throw BackupError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Spezifische Fehlermeldung für Zugriffsprobleme
            if (error as NSError).code == NSFileReadNoPermissionError {
                throw BackupError.accessDenied
            } else {
                throw BackupError.corruptedData
            }
        }
        
        guard let backupData = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupError.invalidFormat
        }
        
        guard let _ = backupData["version"] as? String,
              let rechnungenArray = backupData["rechnungen"] as? [[String: Any]] else {
            throw BackupError.invalidFormat
        }
        
        let context = persistenceController.container.viewContext
        var importedCount = 0
        var updatedCount = 0
        var skippedCount = 0
        
        for rechnungDict in rechnungenArray {
            // Prüfen, ob Rechnung bereits existiert (basierend auf Nummer)
            if let nummer = rechnungDict["nummer"] as? String,
               !nummer.isEmpty,
               let existingRechnung = findRechnung(with: nummer, in: context) {
                // Rechnung existiert - prüfen ob sich Inhalt geändert hat
                if areRechnungenEqual(existingRechnung: existingRechnung, backupDict: rechnungDict) {
                    // Identisch - überspringen
                    skippedCount += 1
                } else {
                    // Geändert - aktualisieren (Backup überschreibt lokal)
                    updateRechnung(existingRechnung, with: rechnungDict)
                    updatedCount += 1
                }
                continue
            }
            
            // Neue Rechnung erstellen
            let neueRechnung = Rechnungen(context: context)
            
            // Textdaten wiederherstellen
            neueRechnung.name = rechnungDict["name"] as? String
            neueRechnung.nummer = rechnungDict["nummer"] as? String
            neueRechnung.status = rechnungDict["status"] as? String
            neueRechnung.iban = rechnungDict["iban"] as? String
            
            // Datumswerte wiederherstellen
            if let datumString = rechnungDict["datum"] as? String {
                neueRechnung.datum = ISO8601DateFormatter().date(from: datumString)
            }
            
            if let faelligkeitString = rechnungDict["faelligkeit"] as? String {
                neueRechnung.faelligkeit = ISO8601DateFormatter().date(from: faelligkeitString)
            }
            
            // Betrag wiederherstellen
            if let summeString = rechnungDict["summe"] as? String {
                neueRechnung.summe = NSDecimalNumber(string: summeString)
            }
            
            // Bilddaten wiederherstellen
            if let bildBase64 = rechnungDict["bild"] as? String,
               let bildData = Data(base64Encoded: bildBase64) {
                neueRechnung.bild = bildData
            }
            
            // PDF-Daten wiederherstellen
            if let pdfBase64 = rechnungDict["pdf"] as? String,
               let pdfData = Data(base64Encoded: pdfBase64) {
                neueRechnung.pdf = pdfData
            }
            
            importedCount += 1
        }
        
        try context.save()
        
        return ImportResult(imported: importedCount, updated: updatedCount, skipped: skippedCount)
    }
    
    private func findRechnung(with nummer: String, in context: NSManagedObjectContext) -> Rechnungen? {
        let fetchRequest: NSFetchRequest<Rechnungen> = Rechnungen.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "nummer == %@", nummer)
        fetchRequest.fetchLimit = 1
        
        do {
            let results = try context.fetch(fetchRequest)
            return results.first
        } catch {
            return nil
        }
    }
    
    private func areRechnungenEqual(existingRechnung: Rechnungen, backupDict: [String: Any]) -> Bool {
        // Textfelder vergleichen
        if (existingRechnung.name ?? "") != (backupDict["name"] as? String ?? "") { return false }
        if (existingRechnung.nummer ?? "") != (backupDict["nummer"] as? String ?? "") { return false }
        if (existingRechnung.status ?? "") != (backupDict["status"] as? String ?? "") { return false }
        if (existingRechnung.iban ?? "") != (backupDict["iban"] as? String ?? "") { return false }
        
        // Datumswerte vergleichen
        let backupDatum: Date?
        if let datumString = backupDict["datum"] as? String {
            backupDatum = ISO8601DateFormatter().date(from: datumString)
        } else {
            backupDatum = nil
        }
        if existingRechnung.datum != backupDatum { return false }
        
        let backupFaelligkeit: Date?
        if let faelligkeitString = backupDict["faelligkeit"] as? String {
            backupFaelligkeit = ISO8601DateFormatter().date(from: faelligkeitString)
        } else {
            backupFaelligkeit = nil
        }
        if existingRechnung.faelligkeit != backupFaelligkeit { return false }
        
        // Betrag vergleichen
        let backupSumme: NSDecimalNumber?
        if let summeString = backupDict["summe"] as? String {
            backupSumme = NSDecimalNumber(string: summeString)
        } else {
            backupSumme = nil
        }
        if existingRechnung.summe != backupSumme { return false }
        
        // Bilddaten vergleichen (via Hash für Performance)
        let backupBildData: Data?
        if let bildBase64 = backupDict["bild"] as? String {
            backupBildData = Data(base64Encoded: bildBase64)
        } else {
            backupBildData = nil
        }
        if existingRechnung.bild != backupBildData { return false }
        
        // PDF-Daten vergleichen (via Hash für Performance)
        let backupPdfData: Data?
        if let pdfBase64 = backupDict["pdf"] as? String {
            backupPdfData = Data(base64Encoded: pdfBase64)
        } else {
            backupPdfData = nil
        }
        if existingRechnung.pdf != backupPdfData { return false }
        
        return true
    }
    
    private func updateRechnung(_ rechnung: Rechnungen, with backupDict: [String: Any]) {
        // Textdaten aktualisieren
        rechnung.name = backupDict["name"] as? String
        rechnung.nummer = backupDict["nummer"] as? String
        rechnung.status = backupDict["status"] as? String
        rechnung.iban = backupDict["iban"] as? String
        
        // Datumswerte aktualisieren
        if let datumString = backupDict["datum"] as? String {
            rechnung.datum = ISO8601DateFormatter().date(from: datumString)
        } else {
            rechnung.datum = nil
        }
        
        if let faelligkeitString = backupDict["faelligkeit"] as? String {
            rechnung.faelligkeit = ISO8601DateFormatter().date(from: faelligkeitString)
        } else {
            rechnung.faelligkeit = nil
        }
        
        // Betrag aktualisieren
        if let summeString = backupDict["summe"] as? String {
            rechnung.summe = NSDecimalNumber(string: summeString)
        } else {
            rechnung.summe = nil
        }
        
        // Bilddaten aktualisieren
        if let bildBase64 = backupDict["bild"] as? String,
           let bildData = Data(base64Encoded: bildBase64) {
            rechnung.bild = bildData
        } else {
            rechnung.bild = nil
        }
        
        // PDF-Daten aktualisieren
        if let pdfBase64 = backupDict["pdf"] as? String,
           let pdfData = Data(base64Encoded: pdfBase64) {
            rechnung.pdf = pdfData
        } else {
            rechnung.pdf = nil
        }
    }
    
    // MARK: - Hilfsfunktionen
    
    func getBackupFiles() -> [URL] {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: documentsPath,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            return files
                .filter { $0.lastPathComponent.hasPrefix("Rechnungen_Backup_") && $0.pathExtension == "json" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }
        } catch {
            return []
        }
    }
    
    func deleteBackupFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
    
    func getBackupInfo(for url: URL) -> BackupInfo? {
        do {
            let data = try Data(contentsOf: url)
            guard let backupData = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            guard let version = backupData["version"] as? String,
                  let exportDateString = backupData["exportDate"] as? String,
                  let exportDate = ISO8601DateFormatter().date(from: exportDateString),
                  let rechnungenArray = backupData["rechnungen"] as? [[String: Any]] else {
                return nil
            }
            
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            
            return BackupInfo(
                url: url,
                version: version,
                exportDate: exportDate,
                rechnungCount: rechnungenArray.count,
                fileSize: Int64(resourceValues.fileSize ?? 0),
                creationDate: resourceValues.creationDate ?? Date()
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Datenstrukturen

struct BackupInfo {
    let url: URL
    let version: String
    let exportDate: Date
    let rechnungCount: Int
    let fileSize: Int64
    let creationDate: Date
    
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var formattedExportDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: exportDate)
    }
}

struct ImportResult {
    let imported: Int
    let updated: Int
    let skipped: Int
    
    var total: Int {
        return imported + updated + skipped
    }
    
    var formattedMessage: String {
        var parts: [String] = []
        
        if imported > 0 {
            parts.append("\(imported) importiert")
        }
        if updated > 0 {
            parts.append("\(updated) aktualisiert")
        }
        if skipped > 0 {
            parts.append("\(skipped) übersprungen")
        }
        
        return parts.isEmpty ? "Keine Änderungen" : parts.joined(separator: ", ")
    }
}

// MARK: - Fehler

enum BackupError: LocalizedError {
    case invalidFormat
    case corruptedData
    case versionMismatch
    case accessDenied
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Ungültiges Backup-Format"
        case .corruptedData:
            return "Backup-Daten beschädigt oder nicht lesbar"
        case .versionMismatch:
            return "Backup-Version nicht kompatibel"
        case .accessDenied:
            return "Keine Zugriffsrechte auf die Backup-Datei"
        }
    }
}

