import Foundation
import CoreImage
import UIKit

/// Generator für GiroCode (EPC-QR-Code) nach Standard EPC069-12
class GiroCodeGenerator {
    
    /// Erwartete IBAN-Länge pro Land (ISO 13616). Unbekannte Länder fallen auf 15...34 zurück.
    private static let ibanLengthsByCountry: [String: Int] = [
        "AL": 28, "AD": 24, "AT": 20, "AZ": 28, "BH": 22, "BY": 28,
        "BE": 16, "BA": 20, "BR": 29, "BG": 22, "CR": 22, "HR": 21,
        "CY": 28, "CZ": 24, "DK": 18, "DO": 28, "EG": 29, "SV": 28,
        "FO": 18, "FI": 18, "FR": 27, "GE": 22, "DE": 22, "GI": 23,
        "GR": 27, "GL": 18, "GT": 28, "HU": 28, "IS": 26, "IQ": 23,
        "IE": 22, "IL": 23, "IT": 27, "JO": 30, "KZ": 20, "XK": 20,
        "KW": 30, "LV": 21, "LB": 28, "LI": 21, "LT": 20, "LU": 20,
        "MK": 19, "MT": 31, "MR": 27, "MU": 30, "MC": 27, "MD": 24,
        "ME": 22, "NL": 18, "NO": 15, "PK": 24, "PS": 29, "PL": 28,
        "PT": 25, "QA": 29, "RO": 24, "SM": 27, "SA": 24, "RS": 22,
        "SK": 24, "SI": 19, "ES": 24, "SE": 24, "CH": 21, "TN": 24,
        "TR": 26, "UA": 29, "GB": 22, "VG": 24
    ]
    
    /// EPC-Vorgabe: Betrag zwischen 0,01 und 999.999.999,99 EUR
    private static let maxEPCAmount = NSDecimalNumber(string: "999999999.99")
    
    /// Formatiert einen Betrag exakt nach EPC-Vorgabe (EUR + Punkt + 2 Nachkommastellen, ohne Double-Umweg)
    static func formattedEPCAmount(_ betrag: Decimal) -> String? {
        let rounding = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 2,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        let rounded = NSDecimalNumber(decimal: betrag).rounding(accordingToBehavior: rounding)
        guard rounded.compare(NSDecimalNumber.zero) == .orderedDescending,
              rounded.compare(maxEPCAmount) != .orderedDescending else {
            return nil
        }
        guard let formatted = epcAmountFormatter.string(from: rounded) else {
            return nil
        }
        return "EUR" + formatted
    }
    
    private static let epcAmountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    /// Generiert einen GiroCode QR-Code für SEPA-Überweisungen
    /// - Parameters:
    ///   - empfaenger: Name des Zahlungsempfängers
    ///   - iban: IBAN des Empfängers
    ///   - betrag: Überweisungsbetrag in Euro
    ///   - verwendungszweck: Verwendungszweck/Referenz
    /// - Returns: UIImage mit QR-Code, oder nil bei Fehler
    static func generateQRCode(empfaenger: String, iban: String, betrag: Decimal, verwendungszweck: String = "") -> UIImage? {
        // IBAN validieren und formatieren (inkl. mod-97-Prüfziffer)
        guard let cleanIBAN = validateAndCleanIBAN(iban),
              !empfaenger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let betragString = formattedEPCAmount(betrag) else {
            return nil
        }
        
        // Empfängername kürzen falls zu lang (max 70 Zeichen)
        let truncatedEmpfaenger = String(empfaenger.prefix(70))
        
        // Verwendungszweck kürzen (max 140 Zeichen)
        let truncatedVerwendungszweck = String(verwendungszweck.prefix(140))
        
        // GiroCode String nach EPC069-12 Standard erstellen
        let giroCodeString = createGiroCodeString(
            empfaenger: truncatedEmpfaenger,
            iban: cleanIBAN,
            betrag: betragString,
            verwendungszweck: truncatedVerwendungszweck
        )
        
        // EPC begrenzt die Nutzdaten auf 331 Bytes
        guard giroCodeString.utf8.count <= 331 else {
            return nil
        }
        
        // QR-Code generieren
        return generateQRCodeImage(from: giroCodeString)
    }
    
    /// Erstellt den GiroCode String nach EPC069-12 Format (12 Zeilen, CRLF-getrennt)
    /// Zeilenumbrüche in den Eingaben werden entfernt, damit keine Felder verrutschen.
    static func createGiroCodeString(empfaenger: String, iban: String, betrag: String, verwendungszweck: String) -> String {
        let safeEmpfaenger = empfaenger
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let safeVerwendungszweck = verwendungszweck
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        
        var lines: [String] = []
        
        lines.append("BCD")                    // Service Tag
        lines.append("002")                    // Version
        lines.append("1")                      // Character Set (UTF-8)
        lines.append("SCT")                    // Identification (SEPA Credit Transfer)
        lines.append("")                       // BIC (optional, leer lassen)
        lines.append(safeEmpfaenger)           // Empfängername
        lines.append(iban)                     // IBAN
        lines.append(betrag)                   // Betrag
        lines.append("")                       // Purpose (optional)
        lines.append("")                       // Structured Reference (optional)
        lines.append(safeVerwendungszweck)     // Unstructured Remittance
        lines.append("")                       // Beneficiary to Originator Information (optional)
        
        return lines.joined(separator: "\r\n")
    }
    
    /// Validiert und bereinigt eine IBAN (inkl. ISO-13616 mod-97-Prüfziffer)
    static func validateAndCleanIBAN(_ iban: String) -> String? {
        // Entferne Leerzeichen und Bindestriche
        let cleanIBAN = iban.replacingOccurrences(of: " ", with: "")
                           .replacingOccurrences(of: "-", with: "")
                           .uppercased()
        
        // Prüfe, ob IBAN mit 2 Buchstaben beginnt (Ländercode)
        guard cleanIBAN.count >= 4,
              let firstChar = cleanIBAN.first,
              let secondChar = cleanIBAN.dropFirst().first,
              firstChar.isLetter && secondChar.isLetter else {
            return nil
        }
        
        // Nur alphanumerische Zeichen erlaubt
        let validCharacters = CharacterSet.alphanumerics
        guard cleanIBAN.unicodeScalars.allSatisfy({ validCharacters.contains($0) }) else {
            return nil
        }
        
        // Längenprüfung: exakt pro Land, sonst Fallback 15-34
        let countryCode = String(cleanIBAN.prefix(2))
        if let expectedLength = ibanLengthsByCountry[countryCode] {
            guard cleanIBAN.count == expectedLength else {
                return nil
            }
        } else {
            guard cleanIBAN.count >= 15 && cleanIBAN.count <= 34 else {
                return nil
            }
        }
        
        // mod-97-Prüfziffer nach ISO 13616 (Rest muss 1 sein)
        guard passesMod97Check(cleanIBAN) else {
            return nil
        }
        
        return cleanIBAN
    }
    
    /// ISO-13616 mod-97-Prüfung: ersten 4 Zeichen ans Ende, Buchstaben als Zahlen (A=10 ... Z=35)
    private static func passesMod97Check(_ iban: String) -> Bool {
        let rearranged = String(iban.dropFirst(4) + iban.prefix(4))
        var remainder = 0
        for char in rearranged {
            if let digit = char.wholeNumberValue {
                remainder = (remainder * 10 + digit) % 97
            } else if let scalar = char.unicodeScalars.first {
                let value = Int(scalar.value) - 55 // A=10, B=11, ... Z=35
                guard value >= 10 && value <= 35 else {
                    return false
                }
                remainder = (remainder * 100 + value) % 97
            } else {
                return false
            }
        }
        return remainder == 1
    }
    
    /// Generiert ein UIImage mit dem QR-Code
    private static func generateQRCodeImage(from string: String) -> UIImage? {
        // EPC deklariert UTF-8 (Character Set "1"), also UTF-8 kodieren
        guard let data = string.data(using: .utf8) else {
            return nil
        }
        
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
        guard let empfaenger = empfaenger, !empfaenger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let iban = iban, !iban.isEmpty,
              let betrag = betrag,
              formattedEPCAmount(betrag.decimalValue) != nil else {
            return false
        }
        
        // IBAN muss gültig sein (inkl. mod-97-Prüfziffer)
        return validateAndCleanIBAN(iban) != nil
    }
    
    /// Maximale Payload für `updateApplicationContext` (Limit ~65 KB, mit Puffer)
    static let maxWatchPayloadBytes = 60_000
    
    /// Erzeugt kompakte QR-Bilddaten für die Watch: längste Seite auf `maxPixelSize`
    /// herunterskaliert, PNG; falls zu groß, kleineres JPEG als Fallback.
    static func generateWatchQRCodeData(empfaenger: String, iban: String, betrag: Decimal, verwendungszweck: String = "", maxPixelSize: CGFloat = 360) -> Data? {
        guard let image = generateQRCode(empfaenger: empfaenger, iban: iban, betrag: betrag, verwendungszweck: verwendungszweck),
              let scaled = image.scaledDown(toMaxPixelSize: maxPixelSize),
              let pngData = scaled.pngData() else {
            return nil
        }
        if pngData.count < maxWatchPayloadBytes {
            return pngData
        }
        // Fallback: kleiner + JPEG
        guard let small = image.scaledDown(toMaxPixelSize: 300),
              let jpegData = small.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        return jpegData
    }
}

private extension UIImage {
    /// Skaliert das Bild so herunter, dass die längste Seite `max` Pixel misst.
    /// Füllt mit Weiß auf (transparent würde den QR-Code unlesbar machen) und
    /// deaktiviert Interpolation, damit die QR-Module scharf bleiben.
    func scaledDown(toMaxPixelSize maxPixels: CGFloat) -> UIImage? {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else { return nil }
        guard longestSide > maxPixels else { return self }
        let scale = maxPixels / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        var format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { context in
            context.cgContext.interpolationQuality = .none
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: newSize))
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
