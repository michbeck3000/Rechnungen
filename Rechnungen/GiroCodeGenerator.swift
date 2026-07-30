import Foundation
import CoreImage
import UIKit

/// Generator für GiroCode (EPC-QR-Code) nach Standard EPC069-12
class GiroCodeGenerator {
    
    /// Generiert einen GiroCode QR-Code für SEPA-Überweisungen
    /// - Parameters:
    ///   - empfaenger: Name des Zahlungsempfängers
    ///   - iban: IBAN des Empfängers
    ///   - betrag: Überweisungsbetrag in Euro
    ///   - verwendungszweck: Verwendungszweck/Referenz
    /// - Returns: UIImage mit QR-Code, oder nil bei Fehler
    static func generateQRCode(empfaenger: String, iban: String, betrag: Decimal, verwendungszweck: String = "") -> UIImage? {
        // IBAN validieren und formatieren
        guard let cleanIBAN = validateAndCleanIBAN(iban) else {
            return nil
        }
        
        // Empfängername kürzen falls zu lang (max 70 Zeichen)
        let truncatedEmpfaenger = String(empfaenger.prefix(70))
        
        // Betrag formatieren (max 2 Dezimalstellen)
        let betragString = String(format: "EUR%.2f", (betrag as NSDecimalNumber).doubleValue)
        
        // Verwendungszweck kürzen (max 140 Zeichen)
        let truncatedVerwendungszweck = String(verwendungszweck.prefix(140))
        
        // GiroCode String nach EPC069-12 Standard erstellen
        let giroCodeString = createGiroCodeString(
            empfaenger: truncatedEmpfaenger,
            iban: cleanIBAN,
            betrag: betragString,
            verwendungszweck: truncatedVerwendungszweck
        )
        
        // QR-Code generieren
        return generateQRCodeImage(from: giroCodeString)
    }
    
    /// Erstellt den GiroCode String nach EPC069-12 Format
    private static func createGiroCodeString(empfaenger: String, iban: String, betrag: String, verwendungszweck: String) -> String {
        var lines: [String] = []
        
        lines.append("BCD")                    // Service Tag
        lines.append("002")                    // Version
        lines.append("1")                      // Character Set (UTF-8)
        lines.append("SCT")                    // Identification (SEPA Credit Transfer)
        lines.append("")                       // BIC (optional, leer lassen)
        lines.append(empfaenger)              // Empfängername
        lines.append(iban)                    // IBAN
        lines.append(betrag)                  // Betrag
        lines.append("")                       // Purpose (optional)
        lines.append("")                       // Structured Reference (optional)
        lines.append(verwendungszweck)        // Unstructured Remittance
        lines.append("")                       // Beneficiary to Originator Information (optional)
        
        return lines.joined(separator: "\n")
    }
    
    /// Validiert und bereinigt eine IBAN
    private static func validateAndCleanIBAN(_ iban: String) -> String? {
        // Entferne Leerzeichen und Bindestriche
        let cleanIBAN = iban.replacingOccurrences(of: " ", with: "")
                           .replacingOccurrences(of: "-", with: "")
                           .uppercased()
        
        // Prüfe Länge (15-34 Zeichen für verschiedene Länder)
        guard cleanIBAN.count >= 15 && cleanIBAN.count <= 34 else {
            return nil
        }
        
        // Prüfe, ob IBAN mit 2 Buchstaben beginnt
        guard let firstChar = cleanIBAN.first,
              let secondChar = cleanIBAN.dropFirst().first,
              firstChar.isLetter && secondChar.isLetter else {
            return nil
        }
        
        // Grundlegende Format-Prüfung (Buchstaben am Anfang, dann Ziffern)
        let validCharacters = CharacterSet.alphanumerics
        guard cleanIBAN.unicodeScalars.allSatisfy({ validCharacters.contains($0) }) else {
            return nil
        }
        
        return cleanIBAN
    }
    
    /// Generiert ein UIImage mit dem QR-Code
    private static func generateQRCodeImage(from string: String) -> UIImage? {
        let data = string.data(using: .isoLatin1)
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel") // Medium error correction
        
        guard let ciImage = filter.outputImage else {
            return nil
        }
        
        // QR-Code hochskalieren für bessere Qualität
        let scale: CGFloat = 10.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledCIImage = ciImage.transformed(by: transform)
        
        // In UIImage konvertieren
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    /// Prüft ob alle notwendigen Daten für einen GiroCode vorhanden sind
    static func canGenerateQRCode(empfaenger: String?, iban: String?, betrag: NSDecimalNumber?) -> Bool {
        guard let empfaenger = empfaenger, !empfaenger.isEmpty,
              let iban = iban, !iban.isEmpty,
              let betrag = betrag, betrag.doubleValue > 0 else {
            return false
        }
        
        // IBAN muss gültig sein
        return validateAndCleanIBAN(iban) != nil
    }
}
