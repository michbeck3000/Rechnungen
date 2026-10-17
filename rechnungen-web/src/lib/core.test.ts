import { describe, expect, it } from 'vitest'
import { formatIBAN, validateAndCleanIBAN } from './iban'
import { formatGermanDecimal, parseGermanDecimal, toEPCAmount } from './decimal'
import { buildGiroCodePayload, createGiroCodeString } from './girocode'
import { parseV1Status } from './backup'
import { toPlainText } from './format'

describe('toPlainText (Kopieren)', () => {
  it('entfernt Steuerzeichen, Zero-Width und BOM', () => {
    expect(toPlainText('Dr.\u0000 Max\u200b')).toBe('Dr. Max')
    expect(toPlainText('\ufeffR-1\u200e')).toBe('R-1')
    expect(toPlainText('Zeile1\u0007\u001f')).toBe('Zeile1')
  })
  it('ersetzt Sonder-Leerzeichen und fasst Leerzeichen zusammen', () => {
    expect(toPlainText('Bitte\u00a0sehr\u00a0\u00a0kurzfristig')).toBe('Bitte sehr kurzfristig')
    expect(toPlainText('  Wert   ')).toBe('Wert')
  })
  it('lässt normale Werte unverändert', () => {
    expect(toPlainText('DE89 3704 0044 0532 0130 00')).toBe('DE89 3704 0044 0532 0130 00')
    expect(toPlainText('1.234,56')).toBe('1.234,56')
  })
})

describe('decimal (Port DecimalParser)', () => {
  it('parst deutsche Beträge', () => {
    expect(parseGermanDecimal('125,50')).toBe(125.5)
    expect(parseGermanDecimal('1.234,56')).toBe(1234.56)
    expect(parseGermanDecimal('125.50')).toBe(125.5) // Punkt wird wie iOS zu Komma
  })
  it('lehnt ungültige Beträge ab', () => {
    expect(parseGermanDecimal('')).toBeNull()
    expect(parseGermanDecimal('0,00')).toBeNull()
    expect(parseGermanDecimal('abc')).toBeNull()
  })
  it('formatiert deutsch', () => {
    expect(formatGermanDecimal(125.5)).toContain('125,50')
  })
  it('EPC-Betrag', () => {
    expect(toEPCAmount(125.5)).toBe('EUR125.50')
    expect(toEPCAmount(0)).toBeNull()
    expect(toEPCAmount(1000000000)).toBeNull()
  })
})

describe('iban', () => {
  it('formatiert in 4er-Blöcke', () => {
    expect(formatIBAN('DE89370400440532013000')).toBe('DE89 3704 0044 0532 0130 00')
  })
  it('validiert echte IBANs (mod-97 + Länge)', () => {
    expect(validateAndCleanIBAN('DE89 3704 0044 0532 0130 00')).toBe('DE89370400440532013000')
    expect(validateAndCleanIBAN('DE00 0000 0000 0000 0000 00')).toBeNull() // falsche Prüfziffer
    expect(validateAndCleanIBAN('DE89')).toBeNull()
  })
})

describe('girocode (Port GiroCodeGenerator)', () => {
  it('erzeugt 12-zeiligen EPC-String', () => {
    const s = createGiroCodeString('Dr. Max', 'DE89370400440532013000', 'EUR125.50', 'R-1')
    expect(s.split('\r\n')).toHaveLength(12)
    expect(s.startsWith('BCD\r\n002\r\n1\r\nSCT')).toBe(true)
  })
  it('baut Payload nur mit gültigen Daten', () => {
    expect(
      buildGiroCodePayload({ empfaenger: 'Dr. Max', iban: 'DE89370400440532013000', betrag: 125.5, verwendungszweck: 'R-1' }),
    ).not.toBeNull()
    expect(
      buildGiroCodePayload({ empfaenger: '', iban: 'DE89370400440532013000', betrag: 125.5 }),
    ).toBeNull()
    expect(
      buildGiroCodePayload({ empfaenger: 'Dr. Max', iban: 'ungültig', betrag: 125.5 }),
    ).toBeNull()
  })
})

describe('backup v1 migration', () => {
  it('mappt Alt-Status', () => {
    expect(parseV1Status('PKV eingereicht, Beihilfe eingereicht')).toEqual(['PKV', 'Beihilfe'])
    expect(parseV1Status('PKV, Bezahlt')).toEqual(['PKV', 'Bezahlt'])
    expect(parseV1Status(undefined)).toEqual([])
  })
})
