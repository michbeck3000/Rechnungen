import { describe, expect, it } from 'vitest'
import { localToRow, rowToLocal } from './sync'
import type { Invoice } from './types'

const sample: Invoice = {
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Dr. Max',
  nummer: 'R-1',
  summe: '125.50',
  datum: '2026-01-05',
  faelligkeit: '2026-02-05',
  status: ['PKV'],
  iban: 'DE89370400440532013000',
  createdAt: '2026-01-05T10:00:00.000Z',
  updatedAt: '2026-01-06T10:00:00.000Z',
}

describe('sync mapping', () => {
  it('local -> row behält UUID als PK, Status als Array', () => {
    const row = localToRow(sample, 'user-1')
    expect(row.id).toBe(sample.id)
    expect(row.user_id).toBe('user-1')
    expect(row.summe).toBe(125.5)
    expect(row.status).toEqual(['PKV'])
    expect(row.bild_path).toBeNull() // kein Blob -> kein Pfad
  })

  it('row -> local rundet Summe auf 2 Stellen, leere Daten -> ""', () => {
    const inv = rowToLocal({
      ...localToRow(sample, 'user-1'),
      summe: 125.5,
      datum: null,
      status: ['PKV', 'Unbekannt'],
    })
    expect(inv.summe).toBe('125.50')
    expect(inv.datum).toBe('')
    expect(inv.status).toEqual(['PKV']) // Unbekannt fällt raus
  })

  it('Roundtrip ist stabil', () => {
    const row = localToRow(sample, 'user-1')
    const back = rowToLocal(row)
    expect(back.id).toBe(sample.id)
    expect(back.summe).toBe(sample.summe)
    expect(back.status).toEqual(sample.status)
  })
})
