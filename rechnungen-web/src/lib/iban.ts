// Port von String+IBAN.swift + GiroCodeGenerator.validateAndCleanIBAN
// (Rechnungen/Extensions/String+IBAN.swift:5-15, GiroCodeGenerator.swift:122-180)

const IBAN_LENGTHS: Record<string, number> = {
  AL: 28, AD: 24, AT: 20, AZ: 28, BH: 22, BY: 28, BE: 16, BA: 20, BR: 29,
  BG: 22, CR: 22, HR: 21, CY: 28, CZ: 24, DK: 18, DO: 28, EG: 29, SV: 28,
  FO: 18, FI: 18, FR: 27, GE: 22, DE: 22, GI: 23, GR: 27, GL: 18, GT: 28,
  HU: 28, IS: 26, IQ: 23, IE: 22, IL: 23, IT: 27, JO: 30, KZ: 20, XK: 20,
  KW: 30, LV: 21, LB: 28, LI: 21, LT: 20, LU: 20, MK: 19, MT: 31, MR: 27,
  MU: 30, MC: 27, MD: 24, ME: 22, NL: 18, NO: 15, PK: 24, PS: 29, PL: 28,
  PT: 25, QA: 29, RO: 24, SM: 27, SA: 24, RS: 22, SK: 24, SI: 19, ES: 24,
  SE: 24, CH: 21, TN: 24, TR: 26, UA: 29, GB: 22, VG: 24,
}

/** "DE89 3704..." -> Blöcke à 4 Zeichen. */
export function formatIBAN(iban: string): string {
  const clean = iban.replace(/\s/g, '')
  let out = ''
  for (let i = 0; i < clean.length; i++) {
    if (i > 0 && i % 4 === 0) out += ' '
    out += clean[i]
  }
  return out
}

/** Bereinigt + validiert (Länderlänge + mod-97). Gibt cleane IBAN oder null zurück. */
export function validateAndCleanIBAN(iban: string): string | null {
  const clean = iban.replace(/[\s-]/g, '').toUpperCase()
  if (clean.length < 4) return null
  if (!/^[A-Z]{2}[A-Z0-9]+$/.test(clean)) return null
  if (!/^[A-Z0-9]+$/.test(clean)) return null

  const country = clean.slice(0, 2)
  const expected = IBAN_LENGTHS[country]
  if (expected !== undefined) {
    if (clean.length !== expected) return null
  } else {
    if (clean.length < 15 || clean.length > 34) return null
  }

  return mod97Check(clean) ? clean : null
}

function mod97Check(iban: string): boolean {
  const rearranged = iban.slice(4) + iban.slice(0, 4)
  let remainder = 0
  for (const ch of rearranged) {
    if (ch >= '0' && ch <= '9') {
      remainder = (remainder * 10 + (ch.charCodeAt(0) - 48)) % 97
    } else {
      const value = ch.charCodeAt(0) - 55 // A=10 … Z=35
      if (value < 10 || value > 35) return false
      remainder = (remainder * 100 + value) % 97
    }
  }
  return remainder === 1
}
