export function formatDateISO(dateISO: string): string {
  if (!dateISO) return 'Kein Datum'
  const d = new Date(dateISO + 'T00:00:00')
  return new Intl.DateTimeFormat('de-DE', { dateStyle: 'medium' }).format(d)
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
