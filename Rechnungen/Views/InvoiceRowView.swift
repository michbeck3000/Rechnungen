import SwiftUI
import CoreData

struct InvoiceRowView: View {
    @ObservedObject var invoice: Rechnungen
    @Environment(\.managedObjectContext) private var viewContext

    @State private var showingDeleteAlert = false
    @State private var showingDuplicateAlert = false
    @State private var showingShareSheet = false
    @State private var pdfURL: URL?
    @State private var isDeleting = false
    @State private var isDuplicating = false
    @State private var isGeneratingPDFFailed = false
    @State private var pdfGenerationError: String = ""
    
    private var isOverdue: Bool {
        guard let dueDate = invoice.faelligkeit else { return false }
        return dueDate < Date()
    }
    
    private var isDueToday: Bool {
        guard let dueDate = invoice.faelligkeit else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
    
    private var dueDateText: String {
        guard let dueDate = invoice.faelligkeit else { return "Kein Fälligkeitsdatum" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        
        if isOverdue {
            return "Überfällig seit \(formatter.string(from: dueDate))"
        } else if isDueToday {
            return "Heute fällig"
        } else {
            return "Fällig am \(formatter.string(from: dueDate))"
        }
    }
    
    private var dueDateColor: Color {
        if isOverdue || isDueToday {
            return .red
        }
        return .primary
    }
    
    var body: some View {
        InvoiceRowContent(
            invoice: invoice,
            dueDateText: dueDateText,
            dueDateColor: dueDateColor
        )
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            InvoiceContextMenu(
                showingShareSheet: $showingShareSheet,
                showingDuplicateAlert: $showingDuplicateAlert,
                showingDeleteAlert: $showingDeleteAlert
            )
        }
        .alert("Rechnung löschen", isPresented: $showingDeleteAlert) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                isDeleting = true
            }
        } message: {
            Text("Möchten Sie diese Rechnung wirklich löschen?")
        }
        .alert("Rechnung duplizieren", isPresented: $showingDuplicateAlert) {
            Button("Abbrechen", role: .cancel) { }
            Button("Duplizieren") {
                isDuplicating = true
            }
        } message: {
            Text("Möchten Sie diese Rechnung duplizieren?")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = pdfURL {
                ShareSheet(activityItems: [url])
            }
        }
        .onChange(of: showingShareSheet) { oldValue, newValue in
            if newValue {
                generatePDF()
            }
        }
        .onChange(of: isDeleting) { oldValue, newValue in
            if newValue {
                deleteInvoice()
            }
        }
        .onChange(of: isDuplicating) { oldValue, newValue in
            if newValue {
                duplicateInvoice()
            }
        }
        .alert("PDF konnte nicht generiert werden", isPresented: $isGeneratingPDFFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(pdfGenerationError)
        }
    }
    
    private func formattedCurrency(_ amount: NSDecimalNumber?) -> String {
        guard let amount = amount else { return "0,00 €" }
        return currencyFormatter.string(from: amount) ?? "0,00 €"
    }
    
    private func generatePDF() {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            let title = invoice.name ?? "Rechnung"
            let number = invoice.nummer ?? ""
            let date = invoice.datum ?? Date()
            let dueDate = invoice.faelligkeit ?? Date()
            let amount = formattedCurrency(invoice.summe)
            let status = invoice.status ?? ""
            let iban = invoice.iban ?? ""
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.locale = Locale(identifier: "de_DE")
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12)
            ]
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18)
            ]
            
            var y: CGFloat = 40
            
            title.draw(at: CGPoint(x: 40, y: y), withAttributes: titleAttributes)
            y += 30
            
            let lines = [
                "Rechnungsnummer: \(number)",
                "Datum: \(dateFormatter.string(from: date))",
                "Fälligkeit: \(dateFormatter.string(from: dueDate))",
                "Betrag: \(amount)",
                "Status: \(status.isEmpty ? "Kein Status" : status)",
                "IBAN: \(iban.formattedIBAN())"
            ]
            
            for line in lines {
                line.draw(at: CGPoint(x: 40, y: y), withAttributes: attributes)
                y += 20
            }
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rechnung_\(invoice.nummer ?? "unknown")")
            .appendingPathExtension("pdf")
        
        do {
            try data.write(to: tempURL)
            pdfURL = tempURL
        } catch {
            pdfGenerationError = "Fehler beim Erstellen der PDF: \(error.localizedDescription)"
            isGeneratingPDFFailed = true
        }
    }
    
    private func deleteInvoice() {
        withAnimation {
            viewContext.delete(invoice)
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Fehler beim Löschen: \(nsError), \(nsError.userInfo)")
            }
        }
        isDeleting = false
    }
    
    private func duplicateInvoice() {
        let neueRechnung = Rechnungen(context: viewContext)
        neueRechnung.name = invoice.name
        neueRechnung.nummer = invoice.nummer
        neueRechnung.summe = invoice.summe
        neueRechnung.datum = Date()
        neueRechnung.faelligkeit = Date()
        neueRechnung.bild = nil
        neueRechnung.pdf = nil
        neueRechnung.status = nil
        neueRechnung.iban = invoice.iban
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("Fehler beim Duplizieren: \(nsError), \(nsError.userInfo)")
        }
        
        isDuplicating = false
    }
}

// MARK: - Subviews
private struct InvoiceRowContent: View {
    let invoice: Rechnungen
    let dueDateText: String
    let dueDateColor: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.name ?? "Unbenannte Rechnung")
                    .font(.headline)
                    .lineLimit(1)
                
                Text(invoice.nummer ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formattedCurrency(invoice.summe))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(dueDateText)
                    .font(.subheadline)
                    .foregroundColor(dueDateColor)
            }
        }
    }
    
    private func formattedCurrency(_ amount: NSDecimalNumber?) -> String {
        guard let amount = amount else { return "0,00 €" }
        return currencyFormatter.string(from: amount) ?? "0,00 €"
    }
}

private struct InvoiceContextMenu: View {
    @Binding var showingShareSheet: Bool
    @Binding var showingDuplicateAlert: Bool
    @Binding var showingDeleteAlert: Bool
    
    var body: some View {
        Group {
            Button(action: {
                showingShareSheet = true
            }) {
                Label("PDF teilen", systemImage: "square.and.arrow.up")
            }
            
            Button(action: {
                showingDuplicateAlert = true
            }) {
                Label("Rechnung duplizieren", systemImage: "doc.on.doc")
            }
            
            Button(role: .destructive, action: {
                showingDeleteAlert = true
            }) {
                Label("Löschen", systemImage: "trash")
            }
        }
    }
}

 
