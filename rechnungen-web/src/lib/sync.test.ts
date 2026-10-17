import { describe, expect, it } from 'vitest'
import { attachPath, buildAttachmentForm, describeError, localToRow, normalizeTimestamp, rowToLocal } from './sync'
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

  it('Anhang-Pfade folgen dem Schema <user>/<id>/bild|pdf', () => {
    const withFiles: Invoice = {
      ...sample,
      bild: new Blob(['x'], { type: 'image/jpeg' }),
      pdf: new Blob(['y'], { type: 'application/pdf' }),
    }
    const row = localToRow(withFiles, 'user-1')
    expect(row.bild_path).toBe('user-1/11111111-1111-4111-8111-111111111111/bild')
    expect(row.pdf_path).toBe(attachPath('user-1', sample.id, 'pdf'))
  })

  it('normalisiert Postgres-Zeitstempel für den Vergleich', () => {
    const remote = normalizeTimestamp('2026-01-06T10:00:00.123456+00:00')
    expect(remote).toBe('2026-01-06T10:00:00.123Z')
    // Vergleich mit lokalem ISO-String ist damit korrekt
    expect(remote! > '2026-01-06T10:00:00.000Z').toBe(true)
    expect(normalizeTimestamp(null)).toBeNull()
    expect(normalizeTimestamp('')).toBeNull()
  })

  it('describeError zeigt Status, Code und Details', () => {
    expect(describeError({ message: 'nope', statusCode: 413, code: 'X', details: 'zu groß' })).toBe('nope · HTTP 413 · Code X · zu groß')
    expect(describeError(new Error('kaputt'))).toBe('kaputt')
    expect(describeError('roh')).toBe('roh')
  })

  it('Anhang-Formular: contentType-Feld vor dem file-Teil (Server-Erwartung)', () => {
    const form = buildAttachmentForm(new Blob(['abc'], { type: 'application/pdf' }), 'application/pdf', 'pdf')
    const entries = [...form.entries()]
    expect(entries.map(([key]) => key)).toEqual(['contentType', 'file'])
    expect(entries[0][1]).toBe('application/pdf')
    const file = entries[1][1] as File
    expect(file.name).toBe('pdf')
    expect(file.type).toBe('application/pdf')
  })
})
