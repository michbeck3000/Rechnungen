// Port von DecimalParser aus Rechnungen/ContentView.swift:1202-1233
// Strikt deutsch: "1.234,56". Kein Double-Umweg (Cent-Rundungsfehler).

/** Parst z.B. "125,50" oder "1.234,56" -> Zahl (als number für Anzeige, String für Speicherung). */
export function parseGermanDecimal(text: string): number | null {
  const trimmed = text.trim()
  if (!trimmed) return null
  if (!/^[\d.,\s]+$/.test(trimmed)) return null
  const noSpaces = trimmed.replace(/\s/g, '')
  let normalized: string
  if (noSpaces.includes(',') && noSpaces.includes('.')) {
    // "1.234,56" -> Tausenderpunkte weg, Komma -> Punkt
    normalized = noSpaces.replace(/\./g, '').replace(',', '.')
  } else if (noSpaces.includes(',')) {
    // "125,50" -> Komma -> Punkt
    normalized = noSpaces.replace(',', '.')
  } else if (noSpaces.includes('.')) {
    // Nur Punkt: "125.50" (englische Eingabe, iOS ersetzt . -> ,) als Dezimal behalten;
    // "1.234" (Tausender ohne Nachkomma) als 1234 werten.
    if (/^\d{1,3}(\.\d{3})+$/.test(noSpaces)) {
      normalized = noSpaces.replace(/\./g, '')
    } else {
      normalized = noSpaces
    }
  } else {
    normalized = noSpaces
  }
  if (!/^\d+(\.\d{1,2})?$/.test(normalized)) return null
  const value = Number(normalized)
  if (!Number.isFinite(value) || value <= 0) return null
  // Auf 2 Stellen runden
  return Math.round(value * 100) / 100
}

/** Formatiert z.B. 125.5 -> "125,50" (de-DE). */
export function formatGermanDecimal(value: number | string): string {
  const num = typeof value === 'string' ? Number(value) : value
  if (!Number.isFinite(num)) return '0,00 €'
  return new Intl.NumberFormat('de-DE', {
    style: 'currency',
    currency: 'EUR',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(num)
}

/** Interner Speicher-String: immer "1234.56" mit Punkt. */
export function toStorageString(value: number): string {
  return value.toFixed(2)
}

/** EPC-Betrag: "EUR1234.56" (en_US_POSIX, 0.01–999999999.99). Port von formattedEPCAmount. */
export function toEPCAmount(value: number | string): string | null {
  const num = typeof value === 'string' ? Number(value) : value
  if (!Number.isFinite(num)) return null
  const rounded = Math.round(num * 100) / 100
  if (rounded < 0.01 || rounded > 999999999.99) return null
  return 'EUR' + rounded.toFixed(2)
}
