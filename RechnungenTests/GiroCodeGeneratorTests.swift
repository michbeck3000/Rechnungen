
import Testing
import Foundation
import UIKit
@testable import Rechnungen

struct GiroCodeGeneratorTests {
    private let validIBAN = "DE89370400440532013000"
    
    // MARK: - IBAN-Prüfung (mod-97)
    
    @Test func testValidGermanIBANAccepted() async throws {
        #expect(GiroCodeGenerator.validateAndCleanIBAN(validIBAN) == validIBAN)
    }
    
    @Test func testValidIBANWithSpacesAndDashesAccepted() async throws {
        #expect(GiroCodeGenerator.validateAndCleanIBAN("DE89 3704-0044 0532 0130 00") == validIBAN)
    }
    
    @Test func testInvalidChecksumRejected() async throws {
        // DE00... scheitert an mod-97
        #expect(GiroCodeGenerator.validateAndCleanIBAN("DE00370400440532013000") == nil)
    }
    
    @Test func testTransposedDigitsRejected() async throws {
        // Vertauschte Ziffern (89 → 98) müssen scheitern
        #expect(GiroCodeGenerator.validateAndCleanIBAN("DE98370400440532013000") == nil)
    }
    
    @Test func testWrongLengthForCountryRejected() async throws {
        // DE muss exakt 22 Zeichen haben
        #expect(GiroCodeGenerator.validateAndCleanIBAN("DE8937040044053201300") == nil)
        #expect(GiroCodeGenerator.validateAndCleanIBAN("DE893704004405320130000") == nil)
    }
    
    @Test func testUnknownCountryFallsBackToLengthRange() async throws {
        #expect(GiroCodeGenerator.validateAndCleanIBAN("XX001234567890123") == nil)
        #expect(GiroCodeGenerator.validateAndCleanIBAN("TOOLONGXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX") == nil)
    }
    
    // MARK: - EPC-Format
    
    @Test func testEPCPayloadHasTwelveCRLFLines() async throws {
        let payload = GiroCodeGenerator.createGiroCodeString(
            empfaenger: "Dr. Max Mustermann",
            iban: validIBAN,
            betrag: "EUR125.50",
            verwendungszweck: "Rechnung 2024-001"
        )
        let lines = payload.components(separatedBy: "\r\n")
        #expect(lines.count == 12)
        #expect(lines[0] == "BCD")
        #expect(lines[1] == "002")
        #expect(lines[2] == "1")
        #expect(lines[3] == "SCT")
        #expect(lines[5] == "Dr. Max Mustermann")
        #expect(lines[6] == validIBAN)
        #expect(lines[7] == "EUR125.50")
        #expect(lines[10] == "Rechnung 2024-001")
        // Keine einzelnen \n oder \r außerhalb von CRLF
        let stripped = payload.replacingOccurrences(of: "\r\n", with: "")
        #expect(!stripped.contains("\n"))
        #expect(!stripped.contains("\r"))
        #expect(payload.utf8.count <= 331)
    }
    
    @Test func testEPCPayloadStripsNewlineInjection() async throws {
        let payload = GiroCodeGenerator.createGiroCodeString(
            empfaenger: "A\nB\rinjected",
            iban: validIBAN,
            betrag: "EUR1.00",
            verwendungszweck: "X\nY"
        )
        #expect(payload.components(separatedBy: "\r\n").count == 12)
        #expect(payload.contains("A B injected"))
        #expect(payload.contains("X Y"))
    }
    
    // MARK: - Betrag (Decimal, kein Double)
    
    @Test func testAmountFormattingExact() async throws {
        #expect(GiroCodeGenerator.formattedEPCAmount(Decimal(12550) / 100) == "EUR125.50")
        #expect(GiroCodeGenerator.formattedEPCAmount(Decimal(1999) / 100) == "EUR19.99")
    }
    
    @Test func testAmountRoundingHalfUp() async throws {
        // 2.675 darf nicht zum Double-Fallstrick 2.67 werden
        #expect(GiroCodeGenerator.formattedEPCAmount(Decimal(2675) / 1000) == "EUR2.68")
    }
    
    @Test func testAmountRangeEnforced() async throws {
        #expect(GiroCodeGenerator.formattedEPCAmount(.zero) == nil)
        #expect(GiroCodeGenerator.formattedEPCAmount(Decimal(-10)) == nil)
        #expect(GiroCodeGenerator.formattedEPCAmount(Decimal(1_000_000_000)) == nil)
        #expect(GiroCodeGenerator.formattedEPCAmount(Decimal(99999999999) / 100) == "EUR999999999.99")
    }
    
    // MARK: - Generierung
    
    @Test func testGenerateQRCodeWithValidData() async throws {
        let image = GiroCodeGenerator.generateQRCode(
            empfaenger: "Dr. Max Mustermann",
            iban: validIBAN,
            betrag: Decimal(12550) / 100,
            verwendungszweck: "Rechnung 2024-001"
        )
        #expect(image != nil)
    }
    
    @Test func testGenerateQRCodeRejectsInvalidIBAN() async throws {
        #expect(GiroCodeGenerator.generateQRCode(
            empfaenger: "Dr. Max Mustermann",
            iban: "DE00370400440532013000",
            betrag: Decimal(12550) / 100
        ) == nil)
    }
    
    @Test func testGenerateQRCodeRejectsEmptyRecipientAndZeroAmount() async throws {
        #expect(GiroCodeGenerator.generateQRCode(empfaenger: "", iban: validIBAN, betrag: Decimal(10)) == nil)
        #expect(GiroCodeGenerator.generateQRCode(empfaenger: "Test", iban: validIBAN, betrag: .zero) == nil)
    }
    
    @Test func testCanGenerateQRCodeConsistent() async throws {
        #expect(GiroCodeGenerator.canGenerateQRCode(empfaenger: "Test", iban: validIBAN, betrag: NSDecimalNumber(string: "125.50")) == true)
        #expect(GiroCodeGenerator.canGenerateQRCode(empfaenger: "Test", iban: "DE00370400440532013000", betrag: NSDecimalNumber(string: "125.50")) == false)
        #expect(GiroCodeGenerator.canGenerateQRCode(empfaenger: "Test", iban: validIBAN, betrag: NSDecimalNumber.zero) == false)
    }
    
    // MARK: - Watch-Payload
    
    @Test func testWatchPayloadFitsApplicationContext() async throws {
        let data = GiroCodeGenerator.generateWatchQRCodeData(
            empfaenger: "Dr. Max Mustermann",
            iban: validIBAN,
            betrag: Decimal(12550) / 100,
            verwendungszweck: "Rechnung 2024-001"
        )
        #expect(data != nil)
        #expect(data!.count < GiroCodeGenerator.maxWatchPayloadBytes)
        #expect(UIImage(data: data!) != nil)
    }
    
    // MARK: - DecimalParser
    
    @Test func testDecimalParserGermanInput() async throws {
        #expect(DecimalParser.parse("125,50") == Decimal(12550) / 100)
        #expect(DecimalParser.parse("1.234,56") == Decimal(123456) / 100)
        #expect(DecimalParser.parse("") == nil)
        #expect(DecimalParser.parse("abc") == nil)
        #expect(DecimalParser.parse("12,34,56") == nil)
    }
}
