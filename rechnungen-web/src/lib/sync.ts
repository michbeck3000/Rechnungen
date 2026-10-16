// Sync: IndexedDB (lokale Wahrheit, offline-fähig) <-> Supabase.
// Strategie: Push dann Pull, Konflikt = neuere updatedAt gewinnt (ISO-Strings
// sind lexikografisch vergleichbar). Löschen läuft über Tombstones/Soft-Delete.
// Anhänge liegen in Supabase Storage (<userId>/<invoiceId>/bild|pdf).
import { db } from './db'
import { supabase } from './supabase'
import type { Invoice, InvoiceStatus } from './types'

export const ATTACH_BUCKET = 'attachments'

export interface RemoteRow {
  id: string
  user_id: string
  name: string
  nummer: string
  summe: number | string
  datum: string | null
  faelligkeit: string | null
  status: string[]
  iban: string
  bild_path: string | null
  pdf_path: string | null
  created_at: string
  updated_at: string
  deleted_at: string | null
}

/** Lokal -> Remote-Zeile (ohne Anhang-Blobs, nur Pfade). */
export function localToRow(inv: Invoice, userId: string): RemoteRow {
  return {
    id: inv.id,
    user_id: userId,
    name: inv.name,
    nummer: inv.nummer,
    summe: Number(inv.summe) || 0,
    datum: inv.datum || null,
    faelligkeit: inv.faelligkeit || null,
    status: [...inv.status],
    iban: inv.iban,
    bild_path: inv.bild ? `${userId}/${inv.id}/bild` : null,
    pdf_path: inv.pdf ? `${userId}/${inv.id}/pdf` : null,
    created_at: inv.createdAt,
    updated_at: inv.updatedAt,
    deleted_at: null,
  }
}

/** Remote-Zeile -> lokal (Blobs werden separat geladen/gesetzt). */
export function rowToLocal(row: RemoteRow): Invoice {
  const status = (row.status ?? []).filter(
    (s): s is InvoiceStatus => s === 'PKV' || s === 'Beihilfe' || s === 'Bezahlt',
  )
  return {
    id: row.id,
    name: row.name ?? '',
    nummer: row.nummer ?? '',
    summe: Number(row.summe).toFixed(2),
    datum: row.datum ?? '',
    faelligkeit: row.faelligkeit ?? '',
    status,
    iban: row.iban ?? '',
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

export type SyncState =
  | { kind: 'idle'; at: string | null }
  | { kind: 'syncing' }
  | { kind: 'error'; message: string }

let state: SyncState = { kind: 'idle', at: loadLast() }
const listeners = new Set<(s: SyncState) => void>()

function setState(s: SyncState) {
  state = s
  listeners.forEach((cb) => cb(s))
}

export function getSyncState(): SyncState {
  return state
}

export function subscribeSync(cb: (s: SyncState) => void): () => void {
  listeners.add(cb)
  cb(state)
  return () => {
    listeners.delete(cb)
  }
}

function lastKey(userId: string) {
  return `sync:last:${userId}`
}

function loadLast(): string | null {
  try {
    return localStorage.getItem('sync:last') ?? null
  } catch {
    return null
  }
}

function loadLastFor(userId: string): string | null {
  try {
    return localStorage.getItem(lastKey(userId)) ?? null
  } catch {
    return null
  }
}

function saveLastFor(userId: string, iso: string) {
  try {
    localStorage.setItem(lastKey(userId), iso)
    localStorage.setItem('sync:last', iso)
  } catch {
    // ignorieren (privater Modus o.ä.)
  }
}

async function downloadBlob(path: string): Promise<Blob | undefined> {
  const { data, error } = await supabase.storage.from(ATTACH_BUCKET).download(path)
  if (error || !data) return undefined
  return data
}

/** Kompletter Sync: Push lokaler Änderungen, dann Pull. Idempotent. */
export async function syncNow(): Promise<void> {
  const { data: session } = await supabase.auth.getSession()
  const user = session.session?.user
  if (!user) return
  if (state.kind === 'syncing') return
  setState({ kind: 'syncing' })
  try {
    const last = loadLastFor(user.id)

    // --- Push: lokale Rechnungen hoch (nur neue/geänderte seit letztem Push) ---
    const locals = await db.invoices.toArray()
    const toPush = last ? locals.filter((l) => l.updatedAt > last) : locals
    for (const inv of toPush) {
      const row = localToRow(inv, user.id)
      if (inv.bild && row.bild_path) {
        const { error } = await supabase.storage
          .from(ATTACH_BUCKET)
          .upload(row.bild_path, inv.bild, { upsert: true, contentType: inv.bildType || inv.bild.type })
        if (error) throw error
      }
      if (inv.pdf && row.pdf_path) {
        const { error } = await supabase.storage
          .from(ATTACH_BUCKET)
          .upload(row.pdf_path, inv.pdf, { upsert: true, contentType: 'application/pdf' })
        if (error) throw error
      }
      const { error } = await supabase.from('invoices').upsert(row)
      if (error) throw error
    }

    // --- Push: Tombstones (gelöschte) als Soft-Delete propagieren ---
    const tombs = await db.tombstones.toArray()
    for (const t of tombs) {
      const { error } = await supabase.from('invoices').upsert({
        id: t.id,
        user_id: user.id,
        updated_at: t.updatedAt,
        deleted_at: t.updatedAt,
      })
      if (error) throw error
    }
    if (tombs.length > 0) await db.tombstones.clear()

    // --- Pull: Remote-Stand holen, neuere gewinnen ---
    const { data: remote, error: pullError } = await supabase.from('invoices').select('*')
    if (pullError) throw pullError
    for (const row of (remote ?? []) as RemoteRow[]) {
      const local = await db.invoices.get(row.id)
      if (row.deleted_at) {
        if (local) await db.invoices.delete(row.id)
        continue
      }
      if (!local || row.updated_at > local.updatedAt) {
        const merged = rowToLocal(row)
        if (row.bild_path) {
          const blob = await downloadBlob(row.bild_path)
          if (blob) {
            merged.bild = blob
            merged.bildType = blob.type
          }
        }
        if (row.pdf_path) {
          const blob = await downloadBlob(row.pdf_path)
          if (blob) {
            merged.pdf = blob
            merged.pdfName = local?.pdfName
          }
        }
        if (!merged.pdfName && row.pdf_path) merged.pdfName = 'Anhang.pdf'
        await db.invoices.put(merged)
      }
    }

    const now = new Date().toISOString()
    saveLastFor(user.id, now)
    setState({ kind: 'idle', at: now })
  } catch (err) {
    setState({ kind: 'error', message: (err as Error).message })
  }
}

// Entprellter Auto-Sync nach lokalen Änderungen (3 s Ruhe).
let timer: ReturnType<typeof setTimeout> | null = null

export function scheduleSync() {
  if (timer) clearTimeout(timer)
  timer = setTimeout(() => {
    timer = null
    syncNow()
  }, 3000)
}
