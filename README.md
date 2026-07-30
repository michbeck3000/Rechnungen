# Rechnungen

iOS-App zur privaten Rechnungsverwaltung mit Fokus auf das deutsche Gesundheitswesen (PKV/Beihilfe) – inklusive Apple Watch-Begleiter.

## Features

- **Rechnungen erfassen & verwalten** mit Foto oder PDF-Anhang
- **Status-Tracking** – PKV eingereicht, Beihilfe eingereicht, bezahlt
- **GiroCode (EPC069-12)** – QR-Code für SEPA-Überweisungen direkt in der App
- **Apple Watch** – QR-Code zum Bezahlen auf der Watch anzeigen
- **iCloud-Sync** via CloudKit
- **Backup & Wiederherstellung** als JSON-Export/Import
- **Suche & Sortierung** – unbezahlte Rechnungen zuerst

## Technologie

| Bereich | Technologie |
|---------|-------------|
| UI | SwiftUI |
| Datenspeicher | Core Data + CloudKit |
| Watch | WatchConnectivity |
| QR-Code | CoreImage (CIQRCodeGenerator) |
| PDF | PDFKit, QuickLook |
| Mindestversion | iOS 17+ / watchOS 10+ |

## Projektstruktur

```
Rechnungen/
├── RechnungenApp.swift          # App-Einstiegspunkt
├── ContentView.swift            # Haupt-Views (Liste, Detail, Formulare)
├── Persistence.swift            # Core Data Stack (CloudKit)
├── BackupManager.swift          # Backup-Export/Import
├── GiroCodeGenerator.swift      # EPC069-12 QR-Code Generator
├── ConnectivityManager.swift    # iPhone-Seite WatchConnectivity
├── Extensions/
│   └── String+IBAN.swift        # IBAN-Formatierung
├── Views/
│   ├── BackupView.swift         # Backup-UI
│   ├── InvoiceRowView.swift     # Rechnungszeile mit Kontextmenü
│   ├── PaymentQRCodeView.swift  # QR-Code-Anzeige
│   └── ShareSheet.swift         # ShareSheet (UIKit-Bridge)
├── Rechnungen.xcdatamodeld/     # Core-Data-Modell
├── RechnungenWatch Watch App/   # watchOS Begleiter-App
├── RechnungenTests/             # Unit Tests (Swift Testing)
└── RechnungenUITests/           # UI Tests (XCTest)
```

## Datenmodell

Eine Core Data Entität `Rechnungen` mit Attributen: `name`, `nummer`, `summe`, `datum`, `faelligkeit`, `status` (komma-separiert), `iban`, `bild`, `pdf`.

## Autor

Michael Seyer – michbeck@seyer-carrera.de
