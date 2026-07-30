import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @State private var backupFiles: [BackupInfo] = []
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false
    @State private var showingDeleteAlert = false
    @State private var backupToDelete: BackupInfo? = nil
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showingErrorAlert = false
    @State private var showingSuccessAlert = false
    @State private var exportedBackupURL: URL?
    
    private let backupManager = BackupManager.shared
    
    var body: some View {
        NavigationStack {
            List {
                // Export-Sektion
                Section("Backup erstellen") {
                    Button {
                        exportBackup()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                            Text("Backup exportieren")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .disabled(isLoading)
                }
                
                // Import-Sektion
                Section("Backup wiederherstellen") {
                    Button {
                        showingImportPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.green)
                            Text("Backup importieren")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .disabled(isLoading)
                }
                
                // Vorhandene Backups
                if !backupFiles.isEmpty {
                    Section("Vorhandene Backups") {
                        ForEach(backupFiles, id: \.url) { backup in
                            BackupRowView(backup: backup) {
                                backupToDelete = backup
                                showingDeleteAlert = true
                            }
                        }
                    }
                }
            }
            .navigationTitle("Backup & Wiederherstellung")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadBackupFiles()
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportedBackupURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .alert("Erfolg", isPresented: $showingSuccessAlert) {
                Button("OK") { }
            } message: {
                if let success = successMessage {
                    Text(success)
                }
            }
            .alert("Fehler", isPresented: $showingErrorAlert) {
                Button("OK") { }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .alert("Backup löschen", isPresented: $showingDeleteAlert) {
                Button("Abbrechen", role: .cancel) {
                    backupToDelete = nil
                }
                Button("Löschen", role: .destructive) {
                    if let backup = backupToDelete {
                        deleteBackup(backup)
                        backupToDelete = nil
                    }
                }
            } message: {
                if let backup = backupToDelete {
                    Text("Backup vom \(backup.formattedExportDate) wirklich löschen?")
                }
            }
            .overlay(
                Group {
                    if isLoading {
                        ProgressView("Lade...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                    }
                }
            )
        }
    }
    
    private func loadBackupFiles() {
        backupFiles = backupManager.getBackupFiles().compactMap { backupManager.getBackupInfo(for: $0) }
    }
    
    private func exportBackup() {
        isLoading = true
        
        Task {
            do {
                let backupURL = try backupManager.exportBackup()
                
                await MainActor.run {
                    isLoading = false
                    exportedBackupURL = backupURL
                    showingExportSheet = true
                    loadBackupFiles() // Liste aktualisieren
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Fehler beim Erstellen des Backups: \(error.localizedDescription)"
                    showingErrorAlert = true
                }
            }
        }
    }
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        isLoading = true
        
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                isLoading = false
                return
            }
            
            Task {
                do {
                    let importResult = try backupManager.importBackup(from: url)
                    
                    await MainActor.run {
                        isLoading = false
                        successMessage = "Erfolgreich: \(importResult.formattedMessage)"
                        showingSuccessAlert = true
                    }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = "Fehler beim Importieren: \(error.localizedDescription)"
                        showingErrorAlert = true
                    }
                }
            }
            
        case .failure(let error):
            isLoading = false
            errorMessage = "Fehler beim Auswählen der Datei: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
    
    private func deleteBackup(_ backup: BackupInfo) {
        do {
            try backupManager.deleteBackupFile(at: backup.url)
            loadBackupFiles()
        } catch {
            errorMessage = "Fehler beim Löschen des Backups: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
}

struct BackupRowView: View {
    let backup: BackupInfo
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Backup")
                    .font(.headline)
                Spacer()
                Text(backup.formattedExportDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(backup.rechnungCount) Rechnungen")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(backup.formattedFileSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }
}

#Preview {
    BackupView()
}
