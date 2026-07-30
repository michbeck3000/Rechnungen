import SwiftUI
import CoreData

struct InvoiceRowView: View {
    @ObservedObject var invoice: Rechnungen
    @Environment(\.managedObjectContext) private var viewContext

    @State private var showingDeleteAlert = false
    @State private var showingDuplicateAlert = false
    @State private var showingShareSheet = false
    @State private var shareText: String = ""
    @State private var isDeleting = false
    @State private var isDuplicating = false
    
    private var pkv: Bool {
        (invoice.status ?? "").contains("PKV")
    }
    
    private var beihilfe: Bool {
        (invoice.status ?? "").contains("Beihilfe")
    }
    
    private var bezahlt: Bool {
        (invoice.status ?? "").contains("Bezahlt")
    }
    
    private var daysUntilDue: String {
        guard let dueDate = invoice.faelligkeit else { return "Kein Datum" }
        if bezahlt { return "bezahlt" }
        let calendar = Calendar.current
        let today = Date()
        let components = calendar.dateComponents([.day], from: today, to: dueDate)
        if let days = components.day {
            if days < 0 { return "überfällig" }
            else if days == 0 { return "heute fällig" }
            else { return "noch \(days) Tage" }
        }
        return "Kein Datum"
    }
    
    private var summeColor: Color {
        if bezahlt { return .green }
        guard let dueDate = invoice.faelligkeit else { return .primary }
        return dueDate < Date() ? .red : .green
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(invoice.name ?? "Unbenannte Rechnung")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(formattedCurrency(invoice.summe))
                    .font(.headline)
                    .foregroundStyle(summeColor)
            }
            HStack(spacing: 12) {
                Text("\(formattedDate(invoice.faelligkeit)) (\(daysUntilDue))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    if pkv {
                        Text("PKV")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    if beihilfe {
                        Text("B")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }
        }
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
            ShareSheet(activityItems: [shareText])
        }
        .onChange(of: showingShareSheet) { oldValue, newValue in
            if newValue {
                prepareShareText()
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
    }
    
    private func formattedCurrency(_ amount: NSDecimalNumber?) -> String {
        guard let amount = amount else { return "0,00 €" }
        return currencyFormatter.string(from: amount) ?? "0,00 €"
    }
    
    private func formattedDate(_ date: Date?) -> String {
        guard let date = date else { return "Kein Datum" }
        return itemFormatter.string(from: date)
    }
    
    private func prepareShareText() {
        let name = invoice.name ?? "Unbenannte Rechnung"
        let number = invoice.nummer ?? ""
        let amount = formattedCurrency(invoice.summe)
        let date = invoice.datum ?? Date()
        let dueDate = invoice.faelligkeit ?? Date()
        let iban = invoice.iban ?? ""
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale(identifier: "de_DE")
        
        var parts = ["Name: \(name)"]
        if !number.isEmpty { parts.append("Verwendungszweck: \(number)") }
        parts.append("Betrag: \(amount)")
        parts.append("Datum: \(dateFormatter.string(from: date))")
        parts.append("Fällig: \(dateFormatter.string(from: dueDate))")
        if !iban.isEmpty { parts.append("IBAN: \(iban.formattedIBAN())") }
        
        shareText = parts.joined(separator: ", ")
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
private struct InvoiceContextMenu: View {
    @Binding var showingShareSheet: Bool
    @Binding var showingDuplicateAlert: Bool
    @Binding var showingDeleteAlert: Bool
    
    var body: some View {
        Group {
            Button(action: {
                showingShareSheet = true
            }) {
                Label("Teilen", systemImage: "square.and.arrow.up")
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

 
