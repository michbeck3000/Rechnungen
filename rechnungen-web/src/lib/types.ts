// Datenmodell v2 – Port des Core-Data-Modells
// (Rechnungen+CoreDataProperties.swift: name, nummer, summe, datum,
//  faelligkeit, status, iban, bild, pdf)
// Neu: stabile UUID als Primärschlüssel, Status als Array, Timestamps.

export type InvoiceStatus = 'PKV' | 'Beihilfe' | 'Bezahlt'

export interface Invoice {
  id: string
  name: string
  nummer: string // Verwendungszweck
  summe: string // Decimal als String ("125.50" intern, Anzeige deutsch)
  datum: string // ISO date (yyyy-mm-dd)
  faelligkeit: string // ISO date
  status: InvoiceStatus[]
  iban: string // raw, ohne Leerzeichen normalisiert
  bildName?: string
  bildType?: string
  bild?: Blob
  pdfName?: string
  pdf?: Blob
  createdAt: string // ISO datetime
  updatedAt: string // ISO datetime
  /** Nur Sync-intern: true = Zeile/Anhänge müssen erneut hoch- bzw. geladen werden. */
  syncPending?: boolean
}

export interface BackupV2 {
  version: '2.0'
  exportDate: string
  rechnungen: InvoiceExport[]
}

// Export-Form: Blobs als base64 (kompatibel zum alten Prinzip aus BackupManager.swift)
export interface InvoiceExport {
  id: string
  name: string
  nummer: string
  summe: string
  datum: string
  faelligkeit: string
  status: InvoiceStatus[]
  iban: string
  bildName?: string
  bildType?: string
  bild?: string // base64
  pdfName?: string
  pdf?: string // base64
  createdAt: string
  updatedAt: string
}

// Altes iOS-Format v1 (BackupManager.swift: createBackupData)
export interface BackupV1Rechnung {
  name?: string
  nummer?: string
  status?: string // "PKV, Bezahlt"
  iban?: string
  datum?: string // ISO8601 datetime
  faelligkeit?: string
  summe?: string
  bild?: string // base64
  pdf?: string // base64
}

export interface BackupV1 {
  version: string
  exportDate: string
  rechnungen: BackupV1Rechnung[]
}

export interface ImportResult {
  imported: number
  updated: number
  skipped: number
}
