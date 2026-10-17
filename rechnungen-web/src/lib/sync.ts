// Sync: IndexedDB (lokale Wahrheit, offline-fähig) <-> Supabase.
// Strategie: Push dann Pull, Konflikt = neuere updatedAt gewinnt. Löschen läuft
// über Tombstones/Soft-Delete, Anhänge liegen in Supabase Storage
// (<userId>/<invoiceId>/bild|pdf).
// Fehler einzelner Anhänge/Zeilen brechen den Lauf nicht ab: sie werden
// gesammelt, gemeldet und über `syncPending` beim nächsten Lauf erneut versucht.
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

/** Pfad eines Anhangs im Storage. */
export function attachPath(userId: string, invoiceId: string, kind: 'bild' | 'pdf'): string {
  return `${userId}/${invoiceId}/${kind}`
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
    bild_path: inv.bild ? attachPath(userId, inv.id, 'bild') : null,
    pdf_path: inv.pdf ? attachPath(userId, inv.id, 'pdf') : null,
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

/**
 * Postgres liefert Zeitstempel als `2026-01-06T10:00:00.123456+00:00`, lokal
 * wird `…Z` geschrieben. Für den lexikografischen Vergleich beides auf
 * ISO-UTC mit Millisekunden normalisieren.
 */
export function normalizeTimestamp(value: string | null | undefined): string | null {
  if (!value) return null
  const d = new Date(value)
  return Number.isNaN(d.getTime()) ? null : d.toISOString()
}

function normalizeRow(row: RemoteRow): RemoteRow {
  return {
    ...row,
    created_at: normalizeTimestamp(row.created_at) ?? row.created_at,
    updated_at: normalizeTimestamp(row.updated_at) ?? row.updated_at,
    deleted_at: normalizeTimestamp(row.deleted_at),
  }
}

/** Fehlermeldung möglichst aussagekräftig machen (Status, Code, Details). */
export function describeError(err: unknown): string {
  if (err && typeof err === 'object') {
    const e = err as { message?: string; statusCode?: string | number; code?: string; details?: string; hint?: string }
    const bits = [
      e.message,
      e.statusCode ? `HTTP ${e.statusCode}` : '',
      e.code ? `Code ${e.code}` : '',
      e.details,
      e.hint,
    ].filter((x): x is string => typeof x === 'string' && x.length > 0)
    if (bits.length > 0) return bits.join(' · ')
  }
  if (err instanceof Error) return err.message
  return String(err)
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

/**
 * Anhang hochladen. Falls `upsert` scheitert (z.B. fehlende UPDATE-Policy oder
 * liegengebliebenes Objekt), einmal aufräumen und neu anlegen.
 */
async function uploadAttachment(path: string, blob: Blob, contentType: string): Promise<unknown | null> {
  const first = await supabase.storage.from(ATTACH_BUCKET).upload(path, blob, { upsert: true, contentType })
  if (!first.error) return null
  await supabase.storage.from(ATTACH_BUCKET).remove([path])
  const second = await supabase.storage.from(ATTACH_BUCKET).upload(path, blob, { upsert: true, contentType })
  if (second.error) {
    return { ...second.error, message: `${describeError(second.error)} (ursprünglich: ${describeError(first.error)})` }
  }
  return null
}

async function removeAttachments(paths: string[]) {
  if (paths.length === 0) return
  // Best effort: nicht vorhandene Objekte sind kein Fehler.
  await supabase.storage.from(ATTACH_BUCKET).remove(paths)
}

async function setPending(id: string, pending: boolean) {
  try {
    await db.invoices.update(id, { syncPending: pending })
  } catch {
    // Record evtl. inzwischen gelöscht – ignorieren
  }
}

/** Kompletter Sync: Push lokaler Änderungen, dann Pull. Idempotent. */
export async function syncNow(): Promise<void> {
  const { data: session } = await supabase.auth.getSession()
  const user = session.session?.user
  if (!user) return
  if (state.kind === 'syncing') return
  setState({ kind: 'syncing' })
  const problems: string[] = []
  try {
    const last = loadLastFor(user.id)

    // --- Push: neue/geänderte Zeilen und solche mit offenen Anhängen ---
    const locals = await db.invoices.toArray()
    const toPush = locals.filter((l) => !last || l.updatedAt > last || l.syncPending === true)
    for (const inv of toPush) {
      const label = inv.name || 'Unbenannt'
      const row = localToRow(inv, user.id)
      const payload: Record<string, unknown> = { ...row }
      let attachmentsOk = true

      if (inv.bild && row.bild_path) {
        const err = await uploadAttachment(row.bild_path, inv.bild, inv.bildType || inv.bild.type || 'image/jpeg')
        if (err) {
          // Pfad nicht mitschicken: Remote-Stand nicht kaputt machen, Retry über syncPending.
          delete payload.bild_path
          attachmentsOk = false
          problems.push(`Foto „${label}“: ${describeError(err)}`)
        }
      }
      if (inv.pdf && row.pdf_path) {
        const err = await uploadAttachment(row.pdf_path, inv.pdf, 'application/pdf')
        if (err) {
          delete payload.pdf_path
          attachmentsOk = false
          problems.push(`PDF „${label}“: ${describeError(err)}`)
        }
      }

      // Entfernte Anhänge auch aus dem Storage räumen (best effort).
      const gone: string[] = []
      if (!inv.bild) gone.push(attachPath(user.id, inv.id, 'bild'))
      if (!inv.pdf) gone.push(attachPath(user.id, inv.id, 'pdf'))
      await removeAttachments(gone)

      const { error } = await supabase.from('invoices').upsert(payload)
      if (error) {
        problems.push(`Rechnung „${label}“: ${describeError(error)}`)
        await setPending(inv.id, true)
        continue
      }
      if (inv.syncPending || !attachmentsOk) await setPending(inv.id, !attachmentsOk)
    }

    // --- Push: Tombstones (gelöschte) als Soft-Delete propagieren ---
    const tombs = await db.tombstones.toArray()
    const doneTombs: string[] = []
    for (const t of tombs) {
      await removeAttachments([attachPath(user.id, t.id, 'bild'), attachPath(user.id, t.id, 'pdf')])
      const { error } = await supabase.from('invoices').upsert({
        id: t.id,
        user_id: user.id,
        updated_at: t.updatedAt,
        deleted_at: t.updatedAt,
      })
      if (error) problems.push(`Löschen: ${describeError(error)}`)
      else doneTombs.push(t.id)
    }
    if (doneTombs.length > 0) await db.tombstones.bulkDelete(doneTombs)

    // --- Pull: Remote-Stand holen, neuere gewinnen ---
    const { data: remote, error: pullError } = await supabase.from('invoices').select('*')
    if (pullError) throw pullError
    for (const raw of (remote ?? []) as RemoteRow[]) {
      const row = normalizeRow(raw)
      const local = await db.invoices.get(row.id)
      if (row.deleted_at) {
        if (local) await db.invoices.delete(row.id)
        continue
      }
      // Anhang-Download fehlgeschlagen? Dann trotz gleichem Stand erneut versuchen.
      const missingAttachment =
        local?.syncPending === true &&
        ((!!row.bild_path && !local.bild) || (!!row.pdf_path && !local.pdf))
      if (local && !missingAttachment && row.updated_at <= local.updatedAt) continue

      const merged = rowToLocal(row)
      let downloadFailed = false
      if (row.bild_path) {
        const blob = await downloadBlob(row.bild_path)
        if (blob) {
          merged.bild = blob
          merged.bildType = blob.type || local?.bildType || 'image/jpeg'
          merged.bildName = local?.bildName
        } else {
          downloadFailed = true
          problems.push(`Foto „${merged.name || 'Unbenannt'}“: Download fehlgeschlagen`)
        }
      }
      // Kein bild_path -> Anhang wurde auf einem anderen Gerät entfernt
      // (merged enthält dann bewusst keinen bild-Schlüssel).
      if (row.pdf_path) {
        const blob = await downloadBlob(row.pdf_path)
        if (blob) {
          merged.pdf = blob
          merged.pdfName = local?.pdfName ?? 'Anhang.pdf'
        } else {
          downloadFailed = true
          problems.push(`PDF „${merged.name || 'Unbenannt'}“: Download fehlgeschlagen`)
        }
      }
      if (downloadFailed) merged.syncPending = true
      await db.invoices.put(merged)
    }

    const now = new Date().toISOString()
    saveLastFor(user.id, now)
    if (problems.length > 0) {
      const shown = problems.slice(0, 3).join(' | ')
      const rest = problems.length > 3 ? ` | +${problems.length - 3} weitere` : ''
      setState({ kind: 'error', message: shown + rest })
    } else {
      setState({ kind: 'idle', at: now })
    }
  } catch (err) {
    setState({ kind: 'error', message: describeError(err) })
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
