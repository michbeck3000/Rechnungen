import SwiftUI
import CoreData
import PhotosUI
import PDFKit
import QuickLook

struct RechnungDetailView: View {
    @ObservedObject var rechnung: Rechnungen
    @State private var showingEditSheet = false
    @State private var showingFullscreenImage = false
    @State private var showingPDFPreview = false
    @State private var showingCopiedAlert = false
    @State private var isDuplicating = false
    @Environment(\.managedObjectContext) private var viewContext
    
    // Optimierte Status-Prüfung mit Caching
    private var statusArray: [String] {
        (rechnung.status ?? "").components(separatedBy: ", ")
    }
    
    private var pkv: Bool {
        statusArray.contains("PKV")
    }
    
    private var beihilfe: Bool {
        statusArray.contains("Beihilfe")
    }
    
    private var bezahlt: Bool {
        statusArray.contains("Bezahlt")
    }
    
    // Optimierte Bildverarbeitung
    private var uiImage: UIImage? {
        guard let bildData = rechnung.bild else { return nil }
        return UIImage(data: bildData)
    }
    
    var body: some View {
        List {
            // Header
            Section {
                Text(rechnung.name ?? "Unbenannte Rechnung")
                    .font(.title)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .textCase(nil)
            
            // Details und Status
            Section {
                if let nummer = rechnung.nummer, !nummer.isEmpty {
                    LabeledContent("Nummer") {
                        HStack(spacing: 4) {
                            Button {
                                UIPasteboard.general.string = nummer
                                showingCopiedAlert = true
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            Text(nummer)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Datum", value: formattedDate(rechnung.datum))
                LabeledContent("Fälligkeit", value: formattedDate(rechnung.faelligkeit))
                LabeledContent("Betrag") {
                    HStack(spacing: 4) {
                        Button {
                            if let summe = rechnung.summe {
                                UIPasteboard.general.string = String(format: "%.2f", summe.doubleValue).replacingOccurrences(of: ".", with: ",")
                                showingCopiedAlert = true
                            }
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                            Text(formattedCurrency(rechnung.summe))
                                .foregroundStyle(.secondary)
                        }
                }
                if let iban = rechnung.iban, !iban.isEmpty {
                    LabeledContent("IBAN") {
                        HStack(spacing: 4) {
                            Button {
                                UIPasteboard.general.string = iban
                                showingCopiedAlert = true
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            Text(iban.formattedIBAN())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Section {
                Toggle("PKV", isOn: Binding(
                    get: { pkv },
                    set: { newValue in updateStatus(pkv: newValue, beihilfe: beihilfe, bezahlt: bezahlt) }
                ))
                .tint(.blue)
                
                Toggle("Beihilfe", isOn: Binding(
                    get: { beihilfe },
                    set: { newValue in updateStatus(pkv: pkv, beihilfe: newValue, bezahlt: bezahlt) }
                ))
                .tint(.blue)
                
                Toggle("Bezahlt", isOn: Binding(
                    get: { bezahlt },
                    set: { newValue in updateStatus(pkv: pkv, beihilfe: beihilfe, bezahlt: newValue) }
                ))
                .tint(.green)
            }
            
            // QR-Code für Zahlung anzeigen
            if GiroCodeGenerator.canGenerateQRCode(empfaenger: rechnung.name, iban: rechnung.iban, betrag: rechnung.summe) {
                Section("Zahlung") {
                    PaymentQRCodeView(
                        empfaenger: rechnung.name,
                        iban: rechnung.iban,
                        betrag: rechnung.summe,
                        verwendungszweck: rechnung.nummer
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                }
            }
            
            
            // Bild anzeigen, wenn vorhanden
            if let image = uiImage {
                Section("Rechnung") {
                    Button {
                        showingFullscreenImage = true
                    } label: {
                        Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.vertical, 8)
                    }
                }
            }
            
            // PDF anzeigen, wenn vorhanden
            if rechnung.pdf != nil {
                Section("PDF") {
                    Button {
                        showingPDFPreview = true
                    } label: {
                        PDFThumbnailView(data: rechnung.pdf!)
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditSheet = true
                } label: {
                    Text("Bearbeiten")
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditRechnungView(rechnung: rechnung, showingEditSheet: $showingEditSheet, isDuplicating: $isDuplicating)
        }
        .fullScreenCover(isPresented: $showingFullscreenImage) {
            NavigationStack {
                ZoomableImageView(image: UIImage(data: rechnung.bild!)!)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") {
                                showingFullscreenImage = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingPDFPreview) {
            if let pdfData = rechnung.pdf {
                PDFPreviewView(data: pdfData)
            }
        }
        .overlay(
            Group {
                if showingCopiedAlert {
                    Text("Kopiert!")
                        .font(.caption)
                        .padding(8)
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                        .shadow(radius: 2)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    showingCopiedAlert = false
                                }
                            }
                        }
                }
            }
        )
        .onAppear {
            sendToWatch()
        }
        .onChange(of: rechnung) { oldValue, newValue in
            sendToWatch()
        }
    }
    
    private func formattedDate(_ date: Date?) -> String {
        guard let date = date else { return "Kein Datum" }
        return itemFormatter.string(from: date)
    }
    
    private func formattedCurrency(_ amount: NSDecimalNumber?) -> String {
        guard let amount = amount else { return "0,00 €" }
        return currencyFormatter.string(from: amount) ?? "0,00 €"
    }
    
    private func updateStatus(pkv: Bool, beihilfe: Bool, bezahlt: Bool) {
        var newStatusArray: [String] = []
        if pkv { newStatusArray.append("PKV") }
        if beihilfe { newStatusArray.append("Beihilfe") }
        if bezahlt { newStatusArray.append("Bezahlt") }
        
        rechnung.status = newStatusArray.isEmpty ? nil : newStatusArray.joined(separator: ", ")
        saveChanges()
    }
    
    private func saveChanges() {
        do {
            try viewContext.save()
        } catch {
            print("Fehler beim Speichern: \(error)")
        }
    }
    
    private func sendToWatch() {
        guard let name = rechnung.name,
              let iban = rechnung.iban,
              let summe = rechnung.summe,
              GiroCodeGenerator.canGenerateQRCode(empfaenger: name, iban: iban, betrag: summe)
        else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let qrImage = GiroCodeGenerator.generateQRCode(
                empfaenger: name,
                iban: iban,
                betrag: summe.decimalValue,
                verwendungszweck: self.rechnung.nummer ?? ""
            ), let imageData = qrImage.pngData() {
                ConnectivityManager.shared.sendInvoiceData(title: name, qrCodeData: imageData)
            }
        }
    }
}

struct StatusBadge: View {
    let status: String
    
    var body: some View {
        if status.isEmpty {
            Text("Kein Status")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.gray.opacity(0.1))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        } else {
            HStack(spacing: 4) {
                ForEach(status.components(separatedBy: ", "), id: \.self) { singleStatus in
                    Text(singleStatus)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(for: singleStatus).opacity(0.15))
                        .foregroundStyle(statusColor(for: singleStatus))
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "pkv":
            return .blue
        case "beihilfe":
            return .indigo
        case "bezahlt":
            return .green
        default:
            return .gray
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

struct NewRechnungView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var showingAddSheet: Bool
    @State private var isDuplicating = false
    
    @State private var name = ""
    @State private var nummer = ""
    @State private var summeText = ""
    @State private var datum = Date()
    @State private var faelligkeit = Date()
    @State private var pkv = false
    @State private var beihilfe = false
    @State private var bezahlt = false
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var isFormValid = false
    @State private var showingDocumentPicker = false
    @State private var selectedPDF: Data?
    @State private var iban = ""
    
    
    var body: some View {
        NavigationStack {
            Form {
                    HStack {
                        TextField("Name", text: $name)
                            .submitLabel(.next)
                            .onChange(of: name) { oldValue, newValue in
                                validateForm()
                            }
                        
                        if name.isEmpty {
                            Text("*")
                                .foregroundStyle(.red)
                                .fontWeight(.bold)
                        }
                    }
                    
                    HStack {
                        TextField("Rechnungsnummer", text: $nummer)
                            .submitLabel(.next)
                            .onChange(of: nummer) { oldValue, newValue in
                                validateForm()
                            }
                        
                        if nummer.isEmpty {
                            Text("*")
                                .foregroundStyle(.red)
                                .fontWeight(.bold)
                        }
                    }
                    
                    HStack {
                        TextField("Betrag (€)", text: $summeText)
                            .keyboardType(.decimalPad)
                            .submitLabel(.done)
                            .onChange(of: summeText) { oldValue, newValue in
                                summeText = newValue.replacingOccurrences(of: ".", with: ",")
                                validateForm()
                            }
                        
                        if !isSummeValid {
                            Text("*")
                                .foregroundStyle(.red)
                                .fontWeight(.bold)
                        }
                    }

                    TextField("IBAN (optional)", text: $iban)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .submitLabel(.done)
                
                Section {
                    DatePicker("Rechnungsdatum", selection: $datum, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                    
                    DatePicker("Fälligkeitsdatum", selection: $faelligkeit, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                }
                
                Section {
                    Toggle("PKV", isOn: $pkv)
                        .tint(.blue)
                    
                    Toggle("Beihilfe", isOn: $beihilfe)
                        .tint(.blue)
                    
                    Toggle("Bezahlt", isOn: $bezahlt)
                        .tint(.green)
                }
                
                Section {
                    if let selectedImage = selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.vertical, 8)
                        
                        Button(role: .destructive) {
                            withAnimation {
                                self.selectedImage = nil
                            }
                        } label: {
                            Label("Bild entfernen", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                            Button {
                                showingCamera = true
                            } label: {
                                HStack {
                                    Image(systemName: "camera")
                                        .font(.title2)
                                    Text("Foto aufnehmen")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                    }
                }
                
                Section {
                    if selectedPDF != nil {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.blue)
                            Text("PDF ausgewählt")
                                .foregroundStyle(.primary)
                            Spacer()
                            Button(role: .destructive) {
                                selectedPDF = nil
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    } else {
                        Button {
                            showingDocumentPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                    .font(.title2)
                                Text("PDF hinzufügen")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                    }
                }
            }
            .navigationTitle("Neue Rechnung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        showingAddSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        if isFormValid {
                            addItem()
                            showingAddSheet = false
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isFormValid)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $selectedImage, sourceType: .photoLibrary)
                    .onDisappear {
                        showingImagePicker = false
                    }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                ImagePicker(selectedImage: $selectedImage, sourceType: .camera)
                    .onDisappear {
                        showingCamera = false
                    }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(selectedPDF: $selectedPDF)
            }
        }
    }
    
    private var isSummeValid: Bool {
        if let summe = Double(summeText.replacingOccurrences(of: ",", with: ".")), summe > 0 {
            return true
        }
        return false
    }
    
    private func validateForm() {
        isFormValid = !name.isEmpty && !nummer.isEmpty && isSummeValid
    }
    
    private func addItem() {
        withAnimation {
            let neueRechnung = Rechnungen(context: viewContext)
            neueRechnung.name = name
            neueRechnung.nummer = nummer
            neueRechnung.datum = datum
            neueRechnung.faelligkeit = faelligkeit
            neueRechnung.iban = iban
            
            
            if let summe = Double(summeText.replacingOccurrences(of: ",", with: ".")) {
                neueRechnung.summe = NSDecimalNumber(value: summe)
            }
            
            if let selectedImage = selectedImage {
                if let imageData = selectedImage.jpegData(compressionQuality: 0.7) {
                    neueRechnung.bild = imageData
                }
            }
            
            neueRechnung.pdf = selectedPDF
            
            var statusArray: [String] = []
            if pkv { statusArray.append("PKV") }
            if beihilfe { statusArray.append("Beihilfe") }
            if bezahlt { statusArray.append("Bezahlt") }
            
            neueRechnung.status = statusArray.isEmpty ? nil : statusArray.joined(separator: ", ")

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Fehler beim Speichern: \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct StatusToggle: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .gray)
            }
        }
    }
}

struct EditRechnungView: View {
    @ObservedObject var rechnung: Rechnungen
    @Binding var showingEditSheet: Bool
    @Binding var isDuplicating: Bool
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var name: String
    @State private var nummer: String
    @State private var summeText: String
    @State private var datum: Date
    @State private var faelligkeit: Date
    @State private var pkv: Bool
    @State private var beihilfe: Bool
    @State private var bezahlt: Bool
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var isFormValid = false
    @State private var showingDocumentPicker = false
    @State private var selectedPDF: Data?
    @State private var iban: String
    
    
    init(rechnung: Rechnungen, showingEditSheet: Binding<Bool>, isDuplicating: Binding<Bool>) {
        self.rechnung = rechnung
        self._showingEditSheet = showingEditSheet
        self._isDuplicating = isDuplicating
        
        let statusArray = (rechnung.status ?? "").components(separatedBy: ", ")
        _name = State(initialValue: rechnung.name ?? "")
        _nummer = State(initialValue: rechnung.nummer ?? "")
        _iban = State(initialValue: rechnung.iban ?? "")
        
        
        let summeValue = rechnung.summe?.doubleValue ?? 0.0
        _summeText = State(initialValue: summeValue == 0.0 ? "" : String(format: "%.2f", summeValue).replacingOccurrences(of: ".", with: ","))
        
        _datum = State(initialValue: rechnung.datum ?? Date())
        _faelligkeit = State(initialValue: rechnung.faelligkeit ?? Date())
        _pkv = State(initialValue: statusArray.contains("PKV"))
        _beihilfe = State(initialValue: statusArray.contains("Beihilfe"))
        _bezahlt = State(initialValue: statusArray.contains("Bezahlt"))
        
        if let bildData = rechnung.bild, let uiImage = UIImage(data: bildData) {
            _selectedImage = State(initialValue: uiImage)
        }
        
        _selectedPDF = State(initialValue: rechnung.pdf)
        
        _isFormValid = State(initialValue: !(rechnung.name?.isEmpty ?? true) && 
                                    !(rechnung.nummer?.isEmpty ?? true) && 
                                    summeValue > 0)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                    HStack {
                        TextField("Name", text: $name)
                            .submitLabel(.next)
                            .onChange(of: name) { oldValue, newValue in
                                validateForm()
                            }
                        
                        if name.isEmpty {
                            Text("*")
                                .foregroundStyle(.red)
                                .fontWeight(.bold)
                        }
                    }
                    
                    HStack {
                        TextField("Rechnungsnummer", text: $nummer)
                            .submitLabel(.next)
                            .onChange(of: nummer) { oldValue, newValue in
                                validateForm()
                            }
                        
                        if nummer.isEmpty {
                            Text("*")
                                .foregroundStyle(.red)
                                .fontWeight(.bold)
                        }
                    }
                    
                    HStack {
                        TextField("Betrag (€)", text: $summeText)
                            .keyboardType(.decimalPad)
                            .submitLabel(.done)
                            .onChange(of: summeText) { oldValue, newValue in
                                summeText = newValue.replacingOccurrences(of: ".", with: ",")
                                validateForm()
                            }
                        
                        if !isSummeValid {
                            Text("*")
                                .foregroundStyle(.red)
                                .fontWeight(.bold)
                        }
                    }

                    TextField("IBAN (optional)", text: $iban)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .submitLabel(.done)
                
                Section {
                    DatePicker("Rechnungsdatum", selection: $datum, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                    
                    DatePicker("Fälligkeitsdatum", selection: $faelligkeit, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                }
                
                Section {
                    Toggle("PKV", isOn: $pkv)
                        .tint(.blue)
                    
                    Toggle("Beihilfe", isOn: $beihilfe)
                        .tint(.blue)
                    
                    Toggle("Bezahlt", isOn: $bezahlt)
                        .tint(.green)
                }
                
                
                Section {
                    if let selectedImage = selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.vertical, 8)
                        
                        Button(role: .destructive) {
                            withAnimation {
                                self.selectedImage = nil
                            }
                        } label: {
                            Label("Bild entfernen", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                            Button {
                                showingCamera = true
                            } label: {
                                HStack {
                                    Image(systemName: "camera")
                                        .font(.title2)
                                    Text("Foto aufnehmen")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                    }
                }
                
                Section {
                    if rechnung.pdf != nil || selectedPDF != nil {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.blue)
                            Text("PDF entfernen")
                                .foregroundStyle(.primary)
                            Spacer()
                            Button(role: .destructive) {
                                rechnung.pdf = nil
                                selectedPDF = nil
                                do {
                                    try viewContext.save()
                                } catch {
                                    print("Fehler beim Löschen der PDF: \(error)")
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    } else {
                        Button {
                            showingDocumentPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                    .font(.title2)
                                Text("PDF hinzufügen")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .navigationTitle(isDuplicating ? "Duplizieren" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        if isDuplicating {
                            viewContext.delete(rechnung)
                            do {
                                try viewContext.save()
                            } catch {
                                print("Fehler beim Löschen: \(error)")
                            }
                        }
                        isDuplicating = false
                        showingEditSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        if isFormValid {
                            updateItem()
                            isDuplicating = false
                            showingEditSheet = false
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isFormValid)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                ImagePicker(selectedImage: $selectedImage, sourceType: .camera)
                    .onDisappear {
                        showingCamera = false
                    }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(selectedPDF: $selectedPDF)
            }
        }
    }
    
    private var isSummeValid: Bool {
        if let summe = Double(summeText.replacingOccurrences(of: ",", with: ".")), summe > 0 {
            return true
        }
        return false
    }
    
    private func validateForm() {
        isFormValid = !name.isEmpty && !nummer.isEmpty && isSummeValid
    }
    
    private func updateItem() {
        withAnimation {
            rechnung.name = name
            rechnung.nummer = nummer
            rechnung.datum = datum
            rechnung.faelligkeit = faelligkeit
            rechnung.iban = iban
            
            
            if let summe = Double(summeText.replacingOccurrences(of: ",", with: ".")) {
                rechnung.summe = NSDecimalNumber(value: summe)
            }
            
            if let selectedImage = selectedImage, let imageData = selectedImage.jpegData(compressionQuality: 0.8) {
                rechnung.bild = imageData
            } else {
                rechnung.bild = nil
            }
            
            if let pdf = selectedPDF {
                rechnung.pdf = pdf
            }
            
            var statusArray: [String] = []
            if pkv { statusArray.append("PKV") }
            if beihilfe { statusArray.append("Beihilfe") }
            if bezahlt { statusArray.append("Bezahlt") }
            
            rechnung.status = statusArray.isEmpty ? nil : statusArray.joined(separator: ", ")
            
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Fehler beim Speichern: \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Rechnungen.status, ascending: true),
            NSSortDescriptor(keyPath: \Rechnungen.faelligkeit, ascending: true)
        ],
        animation: .default)
    private var rechnungenListe: FetchedResults<Rechnungen>
    
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var showingDeleteAlert = false
    @State private var rechnungToDelete: Rechnungen? = nil
    @State private var hasUpdatedStatuses = false
    @State private var rechnungToEdit: Rechnungen? = nil
    @State private var showingEditSheet = false
    @State private var showingSettings = false
    @State private var isDuplicating = false
    
    private var filteredRechnungen: [Rechnungen] {
        let filteredBySearch = rechnungenListe.filter { rechnung in
            if searchText.isEmpty {
                return true
            }
            let searchLowercased = searchText.lowercased()
            return (rechnung.name?.lowercased().contains(searchLowercased) ?? false) ||
                   (rechnung.nummer?.lowercased().contains(searchLowercased) ?? false)
        }
        
        // Teile die Liste in bezahlte und unbezahlte Rechnungen
        let bezahlteRechnungen = filteredBySearch.filter { rechnung in
            guard let status = rechnung.status else { return false }
            return status.contains("Bezahlt")
        }
        
        let unbezahlteRechnungen = filteredBySearch.filter { rechnung in
            guard let status = rechnung.status else { return true }
            return !status.contains("Bezahlt")
        }
        
        // Sortiere unbezahlte Rechnungen nach Fälligkeit
        let sortierteUnbezahlte = unbezahlteRechnungen.sorted { r1, r2 in
            guard let d1 = r1.faelligkeit, let d2 = r2.faelligkeit else { return false }
            return d1 < d2
        }
        
        // Sortiere bezahlte Rechnungen nach Fälligkeitsdatum (jüngstes zuerst)
        let sortierteBezahlte = bezahlteRechnungen.sorted { r1, r2 in
            guard let d1 = r1.faelligkeit, let d2 = r2.faelligkeit else { return false }
            return d1 > d2
        }
        
        return sortierteUnbezahlte + sortierteBezahlte
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Suchfeld und Überschrift als erstes Element
                Section {
                    SearchBar(text: $searchText)
                        .padding(.top, 8)
                        .padding(.bottom, 0)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                
                // Liste der Rechnungen
                ForEach(filteredRechnungen, id: \.self) { rechnung in
                    NavigationLink {
                        RechnungDetailView(rechnung: rechnung)
                    } label: {
                        InvoiceRowView(invoice: rechnung)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .padding(.vertical, 0)
            .navigationTitle("Rechnungen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Neue Rechnung", systemImage: "plus")
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                NewRechnungView(showingAddSheet: $showingAddSheet)
            }
            .sheet(isPresented: $showingEditSheet) {
                if let rechnung = rechnungToEdit {
                    EditRechnungView(rechnung: rechnung, showingEditSheet: $showingEditSheet, isDuplicating: $isDuplicating)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .alert("Rechnung löschen", isPresented: $showingDeleteAlert) {
                Button("Abbrechen", role: .cancel) {
                    rechnungToDelete = nil
                }
                Button("Löschen", role: .destructive) {
                    if let rechnung = rechnungToDelete {
                        deleteItem(rechnung)
                        rechnungToDelete = nil
                    }
                }
            } message: {
                Text("Wirklich löschen?")
            }
        }
        .onAppear {
            if !hasUpdatedStatuses {
                updateExistingStatuses()
                hasUpdatedStatuses = true
            }
        }
    }
    
    // Formatierung für Währung
    private func formattedCurrency(_ amount: NSDecimalNumber?) -> String {
        guard let amount = amount else { return "0,00 €" }
        return currencyFormatter.string(from: amount) ?? "0,00 €"
    }

    private func deleteItem(_ rechnung: Rechnungen) {
        withAnimation {
            viewContext.delete(rechnung)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Fehler beim Löschen: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { rechnungenListe[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Fehler beim Löschen: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func updateExistingStatuses() {
        for rechnung in rechnungenListe {
            if let oldStatus = rechnung.status {
                var newStatus = oldStatus
                    .replacingOccurrences(of: "PKV eingereicht", with: "PKV")
                    .replacingOccurrences(of: "Beihilfe eingereicht", with: "Beihilfe")
                
                // Entferne doppelte Kommas und Leerzeichen
                newStatus = newStatus
                    .replacingOccurrences(of: ", ,", with: ",")
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                
                rechnung.status = newStatus.isEmpty ? nil : newStatus
            }
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Fehler beim Aktualisieren der Status: \(error)")
        }
    }
    
    private func duplicateItem(_ rechnung: Rechnungen) {
        let neueRechnung = Rechnungen(context: viewContext)
        neueRechnung.name = rechnung.name
        neueRechnung.nummer = rechnung.nummer
        neueRechnung.summe = rechnung.summe
        neueRechnung.datum = Date()
        neueRechnung.faelligkeit = Date()
        neueRechnung.bild = nil
        neueRechnung.pdf = nil
        neueRechnung.status = nil
        neueRechnung.iban = rechnung.iban
        
        isDuplicating = true
        rechnungToEdit = neueRechnung
        showingEditSheet = true
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
                .foregroundColor(isSelected ? .accentColor : .primary)
                .clipShape(Capsule())
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            
            TextField("Suchen...", text: $text)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Suchfeld für Rechnungen")
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Suche zurücksetzen")
            }
        }
        .padding(8)
        .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
        .cornerRadius(10)
    }
}

let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    formatter.locale = Locale(identifier: "de_DE")
    return formatter
}()

let currencyFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = Locale(identifier: "de_DE")
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter
}()

// UIViewControllerRepresentable für die Bildauswahl
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    var sourceType: UIImagePickerController.SourceType
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.allowsEditing = false // Deaktiviere das Zuschneiden
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = min(max(scale * delta, 1.0), 4.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newOffset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                            offset = newOffset
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .gesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                }
                            }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedPDF: Data?
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Sicherheitszugriff auf die Datei
            guard url.startAccessingSecurityScopedResource() else {
                print("Kein Zugriff auf die Datei möglich")
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                parent.selectedPDF = data
            } catch {
                print("Fehler beim Lesen der PDF: \(error)")
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

struct PDFKitView: UIViewControllerRepresentable {
    let data: Data
    
    func makeUIViewController(context: Context) -> PDFViewController {
        let pdfViewController = PDFViewController()
        pdfViewController.data = data
        return pdfViewController
    }
    
    func updateUIViewController(_ uiViewController: PDFViewController, context: Context) {}
}

class PDFViewController: UIViewController {
    var data: Data?
    private var pdfView: PDFView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // PDF-View erstellen
        pdfView = PDFView(frame: view.bounds)
        pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true)
        
        // Standard-Auswahlmenü aktivieren
        pdfView.isUserInteractionEnabled = true
        
        // PDF laden
        if let data = data {
            pdfView.document = PDFDocument(data: data)
        }
        
        // View hinzufügen
        view.addSubview(pdfView)
        
        // Toolbar hinzufügen
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)
        
        // Toolbar Constraints
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Toolbar Items
        let copyButton = UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"), style: .plain, target: self, action: #selector(copySelectedText))
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbar.items = [flexSpace, copyButton]
    }
    
    @objc private func copySelectedText() {
        if let selection = pdfView.currentSelection,
           let selectedText = selection.string {
            UIPasteboard.general.string = selectedText
        }
    }
}

struct PDFPreviewView: UIViewControllerRepresentable {
    let data: Data
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        
        // Container View Controller erstellen
        let containerVC = UIViewController()
        containerVC.view.backgroundColor = .systemBackground
        
        // PDF Controller als Child hinzufügen
        containerVC.addChild(controller)
        containerVC.view.addSubview(controller.view)
        controller.didMove(toParent: containerVC)
        
        // Schließen-Button erstellen
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .gray
        closeButton.addTarget(context.coordinator, action: #selector(Coordinator.dismissPreview), for: .touchUpInside)
        
        // Button zur View hinzufügen
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        containerVC.view.addSubview(closeButton)
        
        // View des PDF Controllers für Auto Layout vorbereiten
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Constraints setzen
        NSLayoutConstraint.activate([
            // PDF View Constraints
            controller.view.topAnchor.constraint(equalTo: containerVC.view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: containerVC.view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: containerVC.view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: containerVC.view.bottomAnchor),
            
            // Button Constraints
            closeButton.topAnchor.constraint(equalTo: containerVC.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: containerVC.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // PDF View auf den Vordergrund bringen
        containerVC.view.bringSubviewToFront(closeButton)
        
        return containerVC
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(data: data, dismiss: dismiss)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let data: Data
        let dismiss: DismissAction
        
        init(data: Data, dismiss: DismissAction) {
            self.data = data
            self.dismiss = dismiss
            super.init()
        }
        
        @objc func dismissPreview() {
            dismiss()
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.pdf")
            try? data.write(to: tempURL)
            return tempURL as QLPreviewItem
        }
    }
}

struct PDFThumbnailView: UIViewRepresentable {
    let data: Data
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .systemBackground
        
        // PDF-Thumbnail erstellen
        if let pdfDocument = PDFDocument(data: data),
           let firstPage = pdfDocument.page(at: 0) {
            let pageRect = firstPage.bounds(for: .mediaBox)
            
            // Berechne das Seitenverhältnis
            let aspectRatio = pageRect.width / pageRect.height
            
            // Setze die Größe basierend auf dem Seitenverhältnis
            let targetHeight: CGFloat = 200
            let targetWidth = targetHeight * aspectRatio
            
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetWidth, height: targetHeight))
            
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: CGSize(width: targetWidth, height: targetHeight)))
                
                // Skaliere den Kontext entsprechend
                let scale = targetHeight / pageRect.height
                ctx.cgContext.translateBy(x: 0.0, y: targetHeight)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                
                firstPage.draw(with: .mediaBox, to: ctx.cgContext)
            }
            
            imageView.image = image
        }
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {}
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfUse = false
    @State private var showingAccessibility = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("App-Informationen") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .font(.footnote)
                }
                
                Section("Datenmanagement") {
                    NavigationLink("Backup & Wiederherstellung") {
                        BackupView()
                    }
                    .font(.footnote)
                }
                
                Section("Rechtliches") {
                    Button("Datenschutzerklärung") {
                        showingPrivacyPolicy = true
                    }
                    .font(.footnote)
                    
                    Button("Nutzungsbedingungen") {
                        showingTermsOfUse = true
                    }
                    .font(.footnote)
                    
                    Button("Barrierefreiheit") {
                        showingAccessibility = true
                    }
                    .font(.footnote)
                }
                
                Section("Entwickler") {
                    LabeledContent("Entwickler", value: "Michael Seyer")
                        .font(.footnote)
                    LabeledContent("Website") {
                        Link("www.seyer-carrera.de", destination: URL(string: "https://www.seyer-carrera.de")!)
                    }
                    .font(.footnote)
                    LabeledContent("E-Mail") {
                        Link("michbeck@seyer-carrera.de", destination: URL(string: "mailto:michbeck@seyer-carrera.de")!)
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .font(.body)
                }
            }
            .sheet(isPresented: $showingPrivacyPolicy) {
                PrivacyPolicyView()
            }
            .sheet(isPresented: $showingTermsOfUse) {
                TermsOfUseView()
            }
            .sheet(isPresented: $showingAccessibility) {
                AccessibilityView()
            }
        }
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Datenschutzerklärung")
                        .font(.title)
                        .bold()
                    
                    Group {
                        Text("1. Datenschutz auf einen Blick")
                            .font(.headline)
                        Text("Diese App speichert alle Daten lokal auf Ihrem Gerät. Es werden keine Daten an externe Server übertragen.")
                        
                        Text("2. Datenerfassung")
                            .font(.headline)
                        Text("Die App erfasst und speichert folgende Daten:")
                        Text("• Rechnungsinformationen (Name, Nummer, Betrag, Datum)\n• Status-Informationen\n• Bilder und PDFs der Rechnungen")
                        
                        Text("3. Datenspeicherung")
                            .font(.headline)
                        Text("Alle Daten werden lokal in der Core Data Datenbank Ihres Geräts gespeichert. Die Daten werden nicht mit anderen Geräten synchronisiert oder an Dritte weitergegeben.")
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TermsOfUseView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Nutzungsbedingungen")
                        .font(.title)
                        .bold()
                    
                    Group {
                        Text("1. Allgemeines")
                            .font(.headline)
                        Text("Diese App dient der Verwaltung von Rechnungen und ist ausschließlich für den privaten Gebrauch bestimmt.")
                        
                        Text("2. Haftung")
                            .font(.headline)
                        Text("Der Entwickler übernimmt keine Haftung für die Richtigkeit der eingegebenen Daten oder für eventuelle Verluste von Daten.")
                        
                        Text("3. Nutzung")
                            .font(.headline)
                        Text("Die App darf nur in Übereinstimmung mit geltendem Recht verwendet werden. Der Nutzer ist für die Richtigkeit der eingegebenen Daten selbst verantwortlich.")
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AccessibilityView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Erklärung zur Barrierefreiheit")
                        .font(.title)
                        .bold()
                    
                    Group {
                        Text("1. Konformität")
                            .font(.headline)
                        Text("Diese App wurde in Übereinstimmung mit dem Gesetz zur Gleichstellung von Menschen mit Behinderungen (BGG) und der Barrierefreien-Informationstechnik-Verordnung (BITV 2.0) entwickelt.")
                        
                        Text("2. Umgesetzte Maßnahmen")
                            .font(.headline)
                        Text("Die App wurde mit folgenden barrierefreien Funktionen entwickelt:")
                        Text("• Semantische Beschriftungen für alle wichtigen UI-Elemente\n• Unterstützung für VoiceOver und andere Screenreader\n• Klare Strukturierung der Inhalte\n• Unterstützung für dynamische Schriftgrößen\n• Ausreichende Kontraste für bessere Lesbarkeit")
                        
                        Text("3. Eingeschränkte Barrierefreiheit")
                            .font(.headline)
                        Text("Folgende Bereiche sind möglicherweise nicht vollständig barrierefrei:")
                        Text("• PDF-Dokumente von Drittanbietern\n• Eingescannte Rechnungsbilder\n• Komplexe Tabellen in PDFs")
                        
                        Text("4. Feedback")
                            .font(.headline)
                        Text("Bei Fragen oder Problemen zur Barrierefreiheit kontaktieren Sie uns bitte unter info@michbeck.de")
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
        }
    }
}



