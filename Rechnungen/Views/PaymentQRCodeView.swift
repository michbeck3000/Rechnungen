import SwiftUI

struct PaymentQRCodeView: View {
    let empfaenger: String?
    let iban: String?
    let betrag: NSDecimalNumber?
    let verwendungszweck: String?
    
    @State private var isExpanded = false
    
    private var qrCodeImage: UIImage? {
        guard let empfaenger = empfaenger,
              let iban = iban,
              let betrag = betrag else {
            return nil
        }
        
        let betragDecimal = Decimal(betrag.doubleValue)
        return GiroCodeGenerator.generateQRCode(
            empfaenger: empfaenger,
            iban: iban,
            betrag: betragDecimal,
            verwendungszweck: verwendungszweck ?? ""
        )
    }
    
    var body: some View {
        if GiroCodeGenerator.canGenerateQRCode(empfaenger: empfaenger, iban: iban, betrag: betrag) {
            VStack(spacing: 12) {
                if let qrImage = qrCodeImage {
                    Button {
                        isExpanded = true
                    } label: {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(radius: 2)
                    }
                    
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundStyle(.blue)
                            Text("Mit Banking-App scannen")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let iban = iban {
                            Text(iban.formattedIBAN())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("QR-Code konnte nicht erstellt werden")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $isExpanded) {
                NavigationStack {
                    VStack {
                        if let qrImage = qrCodeImage {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .padding(40)
                        }
                        
                        VStack(spacing: 8) {
                            if let empfaenger = empfaenger {
                                Text("\(empfaenger)")
                                    .font(.footnote)
                            }
                            if let iban = iban {
                                Text(iban.formattedIBAN())
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if let betrag = betrag {
                                Text(currencyFormatter.string(from: betrag) ?? "")
                                    .font(.title2)
                                    .bold()
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding()
                    }
                    .navigationTitle("Zahlungs-QR-Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") {
                                isExpanded = false
                            }
                        }
                    }
                }
            }
        }
    }
    

}

#Preview {
    PaymentQRCodeView(
        empfaenger: "Dr. Max Mustermann",
        iban: "DE89370400440532013000",
        betrag: NSDecimalNumber(value: 125.50),
        verwendungszweck: "Rechnung 2024-001"
    )
}
