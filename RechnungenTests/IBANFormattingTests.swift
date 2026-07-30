
import Testing
@testable import Rechnungen

struct IBANFormattingTests {

    @Test func testFormattedIBAN() async throws {
        let iban = "DE12345678901234567890"
        let expected = "DE12 3456 7890 1234 5678 90"
        #expect(iban.formattedIBAN() == expected)
    }

    @Test func testFormattedIBANWithSpaces() async throws {
        let iban = "DE12 3456 7890 1234 5678 90"
        let expected = "DE12 3456 7890 1234 5678 90"
        #expect(iban.formattedIBAN() == expected)
    }

    @Test func testFormattedIBANShort() async throws {
        let iban = "DE12"
        let expected = "DE12"
        #expect(iban.formattedIBAN() == expected)
    }
    
    @Test func testFormattedIBANEmpty() async throws {
        let iban = ""
        let expected = ""
        #expect(iban.formattedIBAN() == expected)
    }
}
