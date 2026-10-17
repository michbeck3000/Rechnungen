import { db, newId, nowISO } from './db'
import type {
  BackupV1,
  BackupV1Rechnung,
  BackupV2,
  ImportResult,
  Invoice,
  InvoiceExport,
  InvoiceStatus,
} from './types'

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => {
      const result = reader.result as string
      resolve(result.split(',')[1] ?? '')
    }
    reader.onerror = reject
    reader.readAsDataURL(blob)
  })
}

function base64ToBlob(base64: string, type = 'application/octet-stream'): Blob {
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return new Blob([bytes], { type })
}

function dateOnly(iso: string | undefined): string {
  if (!iso) return ''
  return iso.slice(0, 10)
}

/** v1-Status-String ("PKV, Bezahlt") -> Array. Inkl. Alt-Migration "PKV eingereicht". */
export function parseV1Status(status: string | undefined): InvoiceStatus[] {
  if (!status) return []
  const normalized = status
    .replaceAll('PKV eingereicht', 'PKV')
    .replaceAll('Beihilfe eingereicht', 'Beihilfe')
  const out: InvoiceStatus[] = []
  for (const part of normalized.split(',')) {
    const s = part.trim()
    if (s === 'PKV' || s === 'Beihilfe' || s === 'Bezahlt') {
      if (!out.includes(s)) out.push(s)
    }
  }
  return out
}

function v1ToInvoice(r: BackupV1Rechnung): Invoice {
  const now = nowISO()
  return {
    id: newId(),
    name: r.name ?? '',
    nummer: r.nummer ?? '',
    summe: r.summe ?? '0.00',
    datum: dateOnly(r.datum),
    faelligkeit: dateOnly(r.faelligkeit),
    status: parseV1Status(r.status),
    iban: (r.iban ?? '').replace(/\s/g, ''),
    bild: r.bild ? base64ToBlob(r.bild, 'image/jpeg') : undefined,
    pdf: r.pdf ? base64ToBlob(r.pdf, 'application/pdf') : undefined,
    createdAt: now,
    updatedAt: now,
  }
}

function invoicesEqual(a: Invoice, b: Invoice): boolean {
  return (
    a.name === b.name &&
    a.nummer === b.nummer &&
    a.summe === b.summe &&
    a.datum === b.datum &&
    a.faelligkeit === b.faelligkeit &&
    a.iban === b.iban &&
    a.status.join(',') === b.status.join(',')
    // Blobs werden bewusst nicht byte-verglichen (teuer); updatedAt entscheidet
  )
}

/** Export v2 als Datei-Download. */
export async function exportBackupV2(): Promise<void> {
  const invoices = await db.invoices.toArray()
  const rechnungen: InvoiceExport[] = []
  for (const inv of invoices) {
    rechnungen.push({
      id: inv.id,
      name: inv.name,
      nummer: inv.nummer,
      summe: inv.summe,
      datum: inv.datum,
      faelligkeit: inv.faelligkeit,
      status: inv.status,
      iban: inv.iban,
      bildName: inv.bildName,
      bildType: inv.bild?.type,
      bild: inv.bild ? await blobToBase64(inv.bild) : undefined,
      pdfName: inv.pdfName,
      pdf: inv.pdf ? await blobToBase64(inv.pdf) : undefined,
      createdAt: inv.createdAt,
      updatedAt: inv.updatedAt,
    })
  }
  const backup: BackupV2 = {
    version: '2.0',
    exportDate: new Date().toISOString(),
    rechnungen,
  }
  const json = JSON.stringify(backup, null, 2)
  const blob = new Blob([json], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')
  a.href = url
  a.download = `Rechnungen_Backup_v2_${stamp}.json`
  a.click()
  URL.revokeObjectURL(url)
}

/** Import: erkennt v2 und v1 (iOS-Backup). Deduplizierung über nummer, sonst id. */
export async function importBackupFile(file: File): Promise<ImportResult> {
  const text = await file.text()
  const data = JSON.parse(text) as BackupV2 | BackupV1

  let incoming: Invoice[]
  if (data.version === '2.0' && Array.isArray((data as BackupV2).rechnungen)) {
    incoming = (data as BackupV2).rechnungen.map((r) => ({
      id: r.id || newId(),
      name: r.name ?? '',
      nummer: r.nummer ?? '',
      summe: r.summe ?? '0.00',
      datum: r.datum ?? '',
      faelligkeit: r.faelligkeit ?? '',
      status: r.status ?? [],
      iban: r.iban ?? '',
      bildName: r.bildName,
      bildType: r.bildType,
      bild: r.bild ? base64ToBlob(r.bild, r.bildType || 'image/jpeg') : undefined,
      pdfName: r.pdfName,
      pdf: r.pdf ? base64ToBlob(r.pdf, 'application/pdf') : undefined,
      createdAt: r.createdAt ?? nowISO(),
      updatedAt: r.updatedAt ?? nowISO(),
    }))
  } else if (Array.isArray((data as BackupV1).rechnungen)) {
    incoming = (data as BackupV1).rechnungen.map(v1ToInvoice)
  } else {
    throw new Error('Ungültiges Backup-Format')
  }

  let imported = 0
  let updated = 0
  let skipped = 0

  // Importierte Anhänge in jedem Fall (erneut) hochladen – auch wenn der
  // updatedAt-Stand älter als der letzte Sync ist.
  for (const inv of incoming) {
    if (inv.bild || inv.pdf) inv.syncPending = true
  }

  for (const inv of incoming) {
    // 1. per id suchen (v2), 2. per nummer (v1-Kompatibilität)
    let existing: Invoice | undefined = await db.invoices.get(inv.id)
    if (!existing && inv.nummer) {
      existing = await db.invoices.where('nummer').equals(inv.nummer).first()
    }
    if (!existing) {
      await db.invoices.add(inv)
      imported++
    } else if (invoicesEqual(existing, inv)) {
      skipped++
    } else {
      // Backup überschreibt lokal, id bleibt stabil
      await db.invoices.put({ ...inv, id: existing.id })
      updated++
    }
  }

  return { imported, updated, skipped }
}
