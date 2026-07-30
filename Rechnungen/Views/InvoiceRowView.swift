import SwiftUI
import CoreData

struct InvoiceRowView: View {
    @ObservedObject var invoice: Rechnungen
    @State private var showingDeleteAlert = false
    @State private var showingDuplicateAlert = false
    @State private var showingShareSheet = false
    @State private var pdfURL: URL?
    @State private var isDeleting = false
    @State private var isDuplicating = false
    @State private var isSharing = false
    @State private var isGeneratingPDF = false
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
        .onChange(of: isSharing) { oldValue, newValue in
            if newValue {
                generatePDF()
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
        // TODO: Implementiere PDF-Generierung
        isGeneratingPDF = true
    }
    
    private func deleteInvoice() {
        // TODO: Implementiere Löschfunktion
        isDeleting = false
    }
    
    private func duplicateInvoice() {
        // TODO: Implementiere Duplizierungsfunktion
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

 
