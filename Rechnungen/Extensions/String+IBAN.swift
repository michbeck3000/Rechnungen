import Foundation

extension String {
    /// Formatiert eine IBAN durch Hinzufügen von Leerzeichen alle 4 Zeichen
    func formattedIBAN() -> String {
        let clean = self.replacingOccurrences(of: " ", with: "")
        var formatted = ""
        for (index, char) in clean.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted += " "
            }
            formatted.append(char)
        }
        return formatted
    }
}
