export function formatDateISO(dateISO: string): string {
  if (!dateISO) return 'Kein Datum'
  const d = new Date(dateISO + 'T00:00:00')
  return new Intl.DateTimeFormat('de-DE', { dateStyle: 'medium' }).format(d)
}

/**
 * Klartext für die Zwischenablage: entfernt Steuerzeichen, Zero-Width-/Bidi-
 * und BOM-Zeichen, ersetzt Sonder-Leerzeichen und fasst Mehrfach-Leerzeichen
 * zusammen. Werte kommen aus dem iOS-Backup/Einfügungen und enthalten sonst
 * unsichtbare Zeichen, die z.B. Bankformulare stören.
 */
export function toPlainText(input: string): string {
  return input
    // C0/C1-Steuerzeichen (Zeilenumbruch/Tab bleiben erhalten)
    // eslint-disable-next-line no-control-regex -- Steuerzeichen sollen hier bewusst weg
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/g, '')
    // Zero-Width, Bidi-Steuerung, BOM
    .replace(/[\u200B-\u200F\u202A-\u202E\u2060-\u2069\uFEFF]/g, '')
    // Sonder-Leerzeichen -> normales Leerzeichen
    .replace(/[\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]/g, ' ')
    .replace(/[ \t]{2,}/g, ' ')
    .replace(/[ \t]+$/gm, '')
    .trim()
}

export function daysUntilDue(faelligkeit: string, bezahlt: boolean): string {
  if (bezahlt) return 'bezahlt'
  if (!faelligkeit) return 'Kein Datum'
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const due = new Date(faelligkeit + 'T00:00:00')
  const diff = Math.round((due.getTime() - today.getTime()) / 86400000)
  if (diff < 0) return 'überfällig'
  if (diff === 0) return 'heute fällig'
  return `noch ${diff} Tage`
}
