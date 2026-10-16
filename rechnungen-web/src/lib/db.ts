import Dexie, { type Table } from 'dexie'
import type { Invoice } from './types'

export interface Tombstone {
  id: string
  updatedAt: string
}

class RechnungenDB extends Dexie {
  invoices!: Table<Invoice, string>
  tombstones!: Table<Tombstone, string>

  constructor() {
    super('rechnungen-web')
    this.version(1).stores({
      invoices: 'id, nummer, faelligkeit, updatedAt',
    })
    // v2: Tombstones für gelöschte Rechnungen (Sync-Soft-Delete)
    this.version(2).stores({
      invoices: 'id, nummer, faelligkeit, updatedAt',
      tombstones: 'id',
    })
  }
}

export const db = new RechnungenDB()

export async function listInvoices(): Promise<Invoice[]> {
  const all = await db.invoices.toArray()
  // Sortierung wie iOS: unbezahlte nach Fälligkeit aufsteigend, bezahlte absteigend
  const unpaid = all
    .filter((r) => !r.status.includes('Bezahlt'))
    .sort((a, b) => a.faelligkeit.localeCompare(b.faelligkeit))
  const paid = all
    .filter((r) => r.status.includes('Bezahlt'))
    .sort((a, b) => b.faelligkeit.localeCompare(a.faelligkeit))
  return [...unpaid, ...paid]
}

export function newId(): string {
  // crypto.randomUUID gibt es nur in Secure Context (localhost/https).
  // Fallback für http-LAN-Test (z.B. iPhone über IP), damit Import/Formular überall laufen.
  const c = globalThis.crypto as Crypto | undefined
  if (c && typeof c.randomUUID === 'function') {
    try {
      return c.randomUUID()
    } catch {
      // fall through
    }
  }
  if (c && typeof c.getRandomValues === 'function') {
    const b = c.getRandomValues(new Uint8Array(16))
    b[6] = (b[6] & 0x0f) | 0x40 // v4
    b[8] = (b[8] & 0x3f) | 0x80 // variant
    const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
  }
  // Letzter Fallback (kein crypto): Math.random – für lokale IDs ausreichend
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (ch) => {
    const r = (Math.random() * 16) | 0
    const v = ch === 'x' ? r : (r & 0x3) | 0x8
    return v.toString(16)
  })
}

export function todayISO(): string {
  return new Date().toISOString().slice(0, 10)
}

export function nowISO(): string {
  return new Date().toISOString()
}
