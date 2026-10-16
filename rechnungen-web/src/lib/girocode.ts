// Port von GiroCodeGenerator.swift:62-119 (EPC069-12)
// Service Tag BCD / Version 002 / UTF-8 / SCT, 12 Zeilen CRLF-getrennt.
import QRCode from 'qrcode'
import { toEPCAmount } from './decimal'
import { validateAndCleanIBAN } from './iban'

export function createGiroCodeString(
  empfaenger: string,
  iban: string,
  betragEPC: string,
  verwendungszweck = '',
): string {
  const safeEmpfaenger = empfaenger.replace(/[\r\n]/g, ' ')
  const safeZweck = verwendungszweck.replace(/[\r\n]/g, ' ')
  const lines = [
    'BCD',
    '002',
    '1',
    'SCT',
    '',
    safeEmpfaenger,
    iban,
    betragEPC,
    '',
    '',
    safeZweck,
    '',
  ]
  return lines.join('\r\n')
}

export interface GiroInput {
  empfaenger: string
  iban: string
  betrag: number | string
  verwendungszweck?: string
}

export function buildGiroCodePayload(input: GiroInput): string | null {
  const cleanIBAN = validateAndCleanIBAN(input.iban)
  const name = input.empfaenger.trim()
  const betrag = toEPCAmount(input.betrag)
  if (!cleanIBAN || !name || !betrag) return null
  const payload = createGiroCodeString(
    name.slice(0, 70),
    cleanIBAN,
    betrag,
    (input.verwendungszweck ?? '').slice(0, 140),
  )
  if (new TextEncoder().encode(payload).length > 331) return null
  return payload
}

export function canGenerateQRCode(input: GiroInput): boolean {
  return buildGiroCodePayload(input) !== null
}

/** Erzeugt ein QR-PNG als Data-URL (für <img>). */
export async function generateQRDataURL(input: GiroInput): Promise<string | null> {
  const payload = buildGiroCodePayload(input)
  if (!payload) return null
  try {
    return await QRCode.toDataURL(payload, {
      errorCorrectionLevel: 'M',
      margin: 1,
      width: 400,
    })
  } catch {
    return null
  }
}
