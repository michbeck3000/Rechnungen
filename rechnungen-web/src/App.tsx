import { useEffect, useState, type ReactNode } from 'react'
import { useLiveQuery } from 'dexie-react-hooks'
import type { Session } from '@supabase/supabase-js'
import { db, listInvoices, newId, nowISO, todayISO } from './lib/db'
import { formatGermanDecimal, parseGermanDecimal, toStorageString } from './lib/decimal'
import { formatDateISO, toPlainText } from './lib/format'
import { formatIBAN } from './lib/iban'
import { generateQRDataURL } from './lib/girocode'
import { exportBackupV2, importBackupFile } from './lib/backup'
import { supabase } from './lib/supabase'
import { getSyncState, scheduleSync, subscribeSync, syncNow, type SyncState } from './lib/sync'
import type { Invoice, InvoiceStatus } from './lib/types'

type Tab = 'liste' | 'statistik' | 'backup'

/** Ganze Tage bis zur Fälligkeit (negativ = überfällig). */
function daysUntilDue(iso: string): number {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const due = new Date(iso + 'T00:00:00')
  return Math.round((due.getTime() - today.getTime()) / 86400000)
}

/** Rot erst kurz vor / nach der Fälligkeit (< 2 Tage), sonst gelb. */
function dueIsUrgent(inv: Invoice): boolean {
  return !!inv.faelligkeit && daysUntilDue(inv.faelligkeit) < 2
}

function cardStatus(inv: Invoice): { dot: string; text: string; textClass: string } {
  const bezahlt = inv.status.includes('Bezahlt')
  if (bezahlt) return { dot: 'bg-green-500', text: 'BEZAHLT', textClass: 'text-green-600 dark:text-green-400' }
  if (!inv.faelligkeit) return { dot: 'bg-amber-500', text: 'OFFEN', textClass: 'text-amber-600 dark:text-amber-400' }
  const diff = daysUntilDue(inv.faelligkeit)
  if (diff < 0) return { dot: 'bg-red-500', text: 'ÜBERFÄLLIG', textClass: 'text-red-600 dark:text-red-400' }
  if (diff === 0) return { dot: 'bg-red-500', text: 'HEUTE FÄLLIG', textClass: 'text-red-600 dark:text-red-400' }
  if (diff === 1) return { dot: 'bg-red-500', text: 'MORGEN FÄLLIG', textClass: 'text-red-600 dark:text-red-400' }
  return { dot: 'bg-amber-500', text: `FÄLLIG IN ${diff} TAGEN`, textClass: 'text-amber-600 dark:text-amber-400' }
}

export default function App() {
  const [tab, setTab] = useState<Tab>('liste')
  const [search, setSearch] = useState('')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<Invoice | null>(null)
  const [session, setSession] = useState<Session | null>(null)
  const [syncState, setSyncState] = useState<SyncState>(() => getSyncState())

  // Session + Sync-Status abonnieren
  useEffect(() => {
    let cancelled = false
    supabase.auth.getSession().then(({ data }) => {
      if (!cancelled) setSession(data.session)
    })
    // Magic-Link-Rückkehr: Hash wird async verarbeitet – notfalls nachpollen,
    // damit kein manueller Refresh nötig ist.
    const timers: ReturnType<typeof setTimeout>[] = []
    if (/access_token|error_description/.test(window.location.hash)) {
      for (const ms of [800, 2500]) {
        timers.push(
          setTimeout(() => {
            supabase.auth.getSession().then(({ data }) => {
              if (!cancelled && data.session) setSession(data.session)
            })
          }, ms),
        )
      }
    }
    const { data: sub } = supabase.auth.onAuthStateChange((_ev, s) => {
      if (!cancelled) setSession(s)
    })
    return () => {
      cancelled = true
      timers.forEach(clearTimeout)
      sub.subscription.unsubscribe()
    }
  }, [])

  // Token-Hash nach erfolgreichem Login aus der URL entfernen
  useEffect(() => {
    if (session && window.location.hash.includes('access_token')) {
      window.history.replaceState(null, '', window.location.pathname + window.location.search)
    }
  }, [session])

  useEffect(() => subscribeSync(setSyncState), [])

  // Auto-Sync: bei Login, alle 60 s, bei Rückkehr in den Tab
  useEffect(() => {
    if (!session) return
    syncNow()
    const id = setInterval(syncNow, 60000)
    function onVis() {
      if (document.visibilityState === 'visible') syncNow()
    }
    document.addEventListener('visibilitychange', onVis)
    return () => {
      clearInterval(id)
      document.removeEventListener('visibilitychange', onVis)
    }
  }, [session])

  const invoices = useLiveQuery(() => listInvoices(), []) ?? []
  const filtered = invoices.filter((r) => {
    if (!search) return true
    const s = search.toLowerCase()
    return r.name.toLowerCase().includes(s) || r.nummer.toLowerCase().includes(s)
  })
  const selected = invoices.find((r) => r.id === selectedId) ?? null

  // Aktionen-Menüs (native <details>) schließen bei Klick irgendwohin
  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      document.querySelectorAll('details[data-menu][open]').forEach((d) => {
        if (!d.contains(e.target as Node)) d.removeAttribute('open')
      })
    }
    document.addEventListener('click', onDocClick)
    return () => document.removeEventListener('click', onDocClick)
  }, [])

  function closeMenus() {
    document.querySelectorAll('details[data-menu][open]').forEach((d) => d.removeAttribute('open'))
  }

  async function toggleStatus(inv: Invoice, key: InvoiceStatus) {
    const has = inv.status.includes(key)
    const status = has ? inv.status.filter((s) => s !== key) : [...inv.status, key]
    await db.invoices.update(inv.id, { status, updatedAt: nowISO() })
    scheduleSync()
  }

  async function deleteInvoice(id: string) {
    if (!confirm('Wirklich löschen?')) return
    await db.tombstones.put({ id, updatedAt: nowISO() })
    await db.invoices.delete(id)
    setSelectedId(null)
    scheduleSync()
  }

  async function duplicateInvoice(inv: Invoice) {
    // Wie iOS (InvoiceRowView.duplicateInvoice): Stammdaten übernehmen,
    // Datum/Fälligkeit zurücksetzen, Anhänge + Status leeren.
    const now = nowISO()
    const copy: Invoice = {
      ...inv,
      id: newId(),
      datum: todayISO(),
      faelligkeit: todayISO(),
      status: [],
      bild: undefined,
      bildName: undefined,
      bildType: undefined,
      pdf: undefined,
      pdfName: undefined,
      createdAt: now,
      updatedAt: now,
    }
    await db.invoices.add(copy)
    setSelectedId(copy.id)
    scheduleSync()
  }

  async function copyText(raw: string): Promise<boolean> {
    // Immer als Klartext in die Zwischenablage (keine Steuer-/Sonderzeichen).
    const text = toPlainText(raw)
    try {
      await navigator.clipboard.writeText(text)
      return true
    } catch {
      // Fallback für unsicheren Kontext (http-LAN): versteckte Textarea
      try {
        const ta = document.createElement('textarea')
        ta.value = text
        ta.style.position = 'fixed'
        ta.style.opacity = '0'
        document.body.appendChild(ta)
        ta.select()
        const ok = document.execCommand('copy')
        document.body.removeChild(ta)
        return ok
      } catch {
        return false
      }
    }
  }

  function shareText(inv: Invoice): string {
    // Port von InvoiceRowView.prepareShareText
    const parts = [`Name: ${inv.name || 'Unbenannte Rechnung'}`]
    if (inv.nummer) parts.push(`Verwendungszweck: ${inv.nummer}`)
    parts.push(`Betrag: ${formatGermanDecimal(Number(inv.summe))}`)
    if (inv.datum) parts.push(`Datum: ${formatDateISO(inv.datum)}`)
    if (inv.faelligkeit) parts.push(`Fällig: ${formatDateISO(inv.faelligkeit)}`)
    if (inv.iban) parts.push(`IBAN: ${formatIBAN(inv.iban)}`)
    return parts.join(', ')
  }

  if (!session) {
    return (
      <div className="min-h-screen bg-gray-100 text-gray-900 dark:bg-black dark:text-gray-100">
        <header className="border-b border-white/20 bg-gradient-to-b from-white/50 to-white/20 backdrop-blur-2xl backdrop-saturate-150 dark:border-white/10 dark:from-gray-900/50 dark:to-gray-900/20">
          <div className="mx-auto max-w-3xl px-4 py-3">
            <h1 className="text-xl font-semibold tracking-tight">Rechnungen</h1>
          </div>
        </header>
        <main className="mx-auto max-w-3xl px-4 pt-6">
          <LoginView />
        </main>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-100 text-gray-900 dark:bg-black dark:text-gray-100">
      <header className="sticky top-0 z-10 border-b border-white/20 bg-gradient-to-b from-white/50 to-white/20 shadow-[0_1px_16px_rgba(0,0,0,0.06)] backdrop-blur-2xl backdrop-saturate-150 dark:border-white/10 dark:from-gray-900/50 dark:to-gray-900/20">
        <div className="mx-auto flex max-w-3xl items-center gap-2 px-4 py-3">
          <h1 className="text-xl font-semibold tracking-tight">Rechnungen</h1>
          <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-800 dark:text-gray-300">{filtered.length}</span>
        </div>
      </header>

      <main className="mx-auto max-w-3xl px-4 pb-28 pt-3">
        {tab === 'liste' && (
          <>
            {/* Suche – nur in der Listenansicht */}
            {!selected && (
              <div className="relative mb-3">
              <input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Suchen"
                className="w-full rounded-full border border-gray-200 bg-white py-2 pl-9 pr-4 text-[15px] outline-none focus:border-blue-500 dark:border-gray-700 dark:bg-gray-900"
              />
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400">⌕</span>
            </div>
            )}

            {!selected ? (
              <ul className="space-y-3">
                {filtered.map((inv) => {
                  const st = cardStatus(inv)
                  const bezahlt = inv.status.includes('Bezahlt')
                  return (
                    <li key={inv.id} className="rounded-2xl border border-gray-200 bg-white shadow-[0_1px_2px_rgba(0,0,0,0.04)] dark:border-gray-800 dark:bg-gray-900">
                      <button
                        onClick={(e) => {
                          // Falls ein Aktionsmenü offen ist: erster Klick schließt nur,
                          // öffnet nicht versehentlich die Detailansicht.
                          if (document.querySelector('details[data-menu][open]')) {
                            closeMenus()
                            e.preventDefault()
                            return
                          }
                          setSelectedId(inv.id)
                        }}
                        className="block w-full p-4 text-left"
                      >
                        <div className="flex items-baseline justify-between gap-3">
                          <span className="truncate text-[17px] font-medium text-gray-900 dark:text-gray-50">{inv.name || 'Unbenannt'}</span>
                          <span className={`shrink-0 text-[17px] font-semibold tabular-nums ${bezahlt ? 'text-gray-900 dark:text-gray-50' : dueIsUrgent(inv) ? 'text-red-600 dark:text-red-400' : 'text-amber-600 dark:text-amber-400'}`}>
                            {formatGermanDecimal(Number(inv.summe))}
                          </span>
                        </div>
                        <div className="mt-0.5 text-[15px] text-gray-900 dark:text-gray-200">
                          {formatDateISO(inv.faelligkeit)}
                        </div>
                      </button>
                      <div className="flex items-center gap-2 rounded-b-2xl border-t border-gray-100 bg-gray-50/60 px-4 py-2 dark:border-gray-800 dark:bg-gray-800/40">
                        <span className={`h-2.5 w-2.5 shrink-0 rounded-full ${st.dot}`} />
                        <span className={`text-[13px] font-medium tracking-wide ${st.textClass}`}>{st.text}</span>
                        <span className="ml-auto flex items-center gap-1">
                          {inv.status.filter((s) => s !== 'Bezahlt').map((s) => (
                            <span key={s} className="rounded-full bg-blue-50 px-2 py-0.5 text-[11px] font-medium text-blue-700 dark:bg-blue-950 dark:text-blue-300">
                              {s === 'Beihilfe' ? 'B' : s}
                            </span>
                          ))}
                          <details data-menu className="relative">
                            <summary className="cursor-pointer list-none rounded-full px-2 py-0.5 text-base leading-none text-gray-400 hover:bg-gray-200 hover:text-gray-700 dark:hover:bg-gray-700 dark:hover:text-gray-200 [&::-webkit-details-marker]:hidden">
                              ···
                            </summary>
                            <div className="absolute right-0 z-20 flex w-44 flex-col divide-y divide-gray-100 rounded-xl border border-gray-200 bg-white py-1 text-[13px] shadow-lg dark:divide-gray-800 dark:border-gray-700 dark:bg-gray-900">
                              <button
                                onClick={() => { copyText(shareText(inv)); closeMenus() }}
                                className="px-3 py-2 text-left hover:bg-gray-50 dark:hover:bg-gray-800"
                              >
                                Kopieren
                              </button>
                              <button
                                onClick={() => { duplicateInvoice(inv); closeMenus() }}
                                className="px-3 py-2 text-left hover:bg-gray-50 dark:hover:bg-gray-800"
                              >
                                Duplizieren
                              </button>
                              <button
                                onClick={() => deleteInvoice(inv.id)}
                                className="px-3 py-2 text-left text-red-600 hover:bg-red-50 dark:hover:bg-red-950"
                              >
                                Löschen
                              </button>
                            </div>
                          </details>
                        </span>
                      </div>
                    </li>
                  )
                })}
                {filtered.length === 0 && <p className="py-10 text-center text-gray-500">Keine Rechnungen. Lege eine an oder importiere ein Backup.</p>}
              </ul>
            ) : (
              <DetailView
                invoice={selected}
                onBack={() => setSelectedId(null)}
                onToggle={toggleStatus}
                onEdit={() => { setEditing(selected); setShowForm(true) }}
                onDelete={() => deleteInvoice(selected.id)}
                onDuplicate={() => duplicateInvoice(selected)}
                onCopyField={copyText}
                onCopyAll={() => copyText(shareText(selected))}
              />
            )}
          </>
        )}

        {tab === 'statistik' && <StatsView invoices={invoices} />}
        {tab === 'backup' && <BackupView email={session?.user.email ?? ''} syncState={syncState} />}
      </main>

      {/* FAB wie im Beispiel */}
      {tab === 'liste' && !selected && (
        <button
          onClick={() => { setEditing(null); setShowForm(true) }}
          aria-label="Neue Rechnung"
          className="fixed bottom-24 right-5 z-20 flex h-14 w-14 items-center justify-center rounded-full bg-black text-3xl font-light text-white shadow-lg hover:bg-gray-800 dark:bg-white dark:text-black"
        >
          +
        </button>
      )}

      {/* Bottom-Navigation wie im Beispiel */}
      <nav className="fixed inset-x-0 bottom-0 z-10 border-t border-white/20 bg-gradient-to-t from-white/50 to-white/20 shadow-[0_-1px_16px_rgba(0,0,0,0.06)] backdrop-blur-2xl backdrop-saturate-150 dark:border-white/10 dark:from-gray-900/50 dark:to-gray-900/20">
        <div className="mx-auto grid max-w-3xl grid-cols-3">
          {([
            { key: 'liste', label: 'Rechnungen', icon: (
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} className="h-6 w-6" aria-hidden="true">
                <path strokeLinecap="round" strokeLinejoin="round" d="M9 12h6M9 16h6M13 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9l-6-6z" />
                <path strokeLinecap="round" strokeLinejoin="round" d="M13 3v6h6" />
              </svg>
            ) },
            { key: 'statistik', label: 'Statistik', icon: (
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} className="h-6 w-6" aria-hidden="true">
                <path strokeLinecap="round" d="M4 20V10M10 20V4M16 20v-8M22 20H2" />
              </svg>
            ) },
            { key: 'backup', label: 'Einstellungen', icon: (
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} className="h-6 w-6" aria-hidden="true">
                <circle cx="12" cy="12" r="3" />
                <path strokeLinecap="round" strokeLinejoin="round" d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z" />
              </svg>
            ) },
          ] as { key: Tab; label: string; icon: ReactNode }[]).map((item) => (
            <button
              key={item.key}
              onClick={() => { setTab(item.key); setSelectedId(null) }}
              className={`flex flex-col items-center gap-0.5 py-2 text-[11px] ${tab === item.key ? 'font-semibold text-blue-600 dark:text-blue-400' : 'text-gray-400'}`}
            >
              {item.icon}
              {item.label}
            </button>
          ))}
        </div>
      </nav>

      {showForm && (
        <InvoiceForm
          initial={editing}
          onClose={() => { setShowForm(false); setEditing(null) }}
          onSaved={(id) => { setShowForm(false); setEditing(null); setSelectedId(id); setTab('liste') }}
        />
      )}
    </div>
  )
}

function DetailView({ invoice, onBack, onToggle, onEdit, onDelete, onDuplicate, onCopyField, onCopyAll }: {
  invoice: Invoice
  onBack: () => void
  onToggle: (inv: Invoice, key: InvoiceStatus) => void
  onEdit: () => void
  onDelete: () => void
  onDuplicate: () => void
  onCopyField: (text: string) => Promise<boolean>
  onCopyAll: () => Promise<boolean>
}) {
  const [qrUrl, setQrUrl] = useState<string | null>(null)
  const [imgUrl, setImgUrl] = useState<string | null>(null)
  const [pdfUrl, setPdfUrl] = useState<string | null>(null)
  const [copied, setCopied] = useState<string | null>(null)

  useEffect(() => {
    let alive = true
    generateQRDataURL({
      empfaenger: invoice.name,
      iban: invoice.iban,
      betrag: Number(invoice.summe),
      verwendungszweck: invoice.nummer,
    }).then((url) => { if (alive) setQrUrl(url) })
    const imgs: string[] = []
    if (invoice.bild) {
      const u = URL.createObjectURL(invoice.bild)
      imgs.push(u)
      setImgUrl(u)
    } else setImgUrl(null)
    if (invoice.pdf) {
      const u = URL.createObjectURL(invoice.pdf)
      imgs.push(u)
      setPdfUrl(u)
    } else setPdfUrl(null)
    return () => { alive = false; imgs.forEach((u) => URL.revokeObjectURL(u)) }
  }, [invoice])

  function copy(text: string, label: string) {
    onCopyField(text).then((ok) => {
      if (ok) {
        setCopied(label)
        setTimeout(() => setCopied(null), 1500)
      }
    })
  }

  function copyAll() {
    onCopyAll().then((ok) => {
      if (ok) {
        setCopied('Rechnung')
        setTimeout(() => setCopied(null), 1500)
      }
    })
  }

  function closeDetailMenu() {
    document.querySelectorAll('details[data-menu][open]').forEach((d) => d.removeAttribute('open'))
  }

  return (
    <div className="relative space-y-3">
      <div className="flex items-center gap-2">
        <button onClick={onBack} className="rounded-full border border-gray-200 bg-white px-4 py-1.5 text-sm dark:border-gray-700 dark:bg-gray-900">Zurück</button>
        <div className="flex flex-1 justify-center">
          <button onClick={onEdit} className="rounded-full bg-black px-6 py-1.5 text-sm font-semibold text-white dark:bg-white dark:text-black">Bearbeiten</button>
        </div>
        <details data-menu className="relative ml-auto">
          <summary className="cursor-pointer list-none rounded-full border border-gray-200 bg-white px-3 py-1.5 text-base leading-none text-gray-500 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300 [&::-webkit-details-marker]:hidden">
            ···
          </summary>
          <div className="absolute right-0 z-20 flex w-44 flex-col divide-y divide-gray-100 rounded-xl border border-gray-200 bg-white py-1 text-[13px] shadow-lg dark:divide-gray-800 dark:border-gray-700 dark:bg-gray-900">
            <button
              onClick={() => { copyAll(); closeDetailMenu() }}
              className="px-3 py-2 text-left hover:bg-gray-50 dark:hover:bg-gray-800"
            >
              Kopieren
            </button>
            <button
              onClick={onDuplicate}
              className="px-3 py-2 text-left hover:bg-gray-50 dark:hover:bg-gray-800"
            >
              Duplizieren
            </button>
            <button
              onClick={onDelete}
              className="px-3 py-2 text-left text-red-600 hover:bg-red-50 dark:hover:bg-red-950"
            >
              Löschen
            </button>
          </div>
        </details>
      </div>
      {copied && (
        <div className="pointer-events-none absolute inset-x-0 top-12 z-30 flex justify-center">
          <p className="rounded-full bg-black/85 px-4 py-2 text-sm text-white shadow-lg dark:bg-white/90 dark:text-black">
            Kopiert: {copied}
          </p>
        </div>
      )}

      <div className="rounded-2xl border border-gray-200 bg-white p-4 dark:border-gray-800 dark:bg-gray-900">
        <button
          onClick={() => copy(invoice.name || 'Unbenannt', 'Name')}
          title="Name kopieren"
          className="flex w-full items-start gap-2 text-left"
        >
          <span className="break-words text-lg font-bold">{invoice.name || 'Unbenannt'}</span>
          <span className="mt-0.5 text-blue-600">⧉</span>
        </button>
        <dl className="mt-3 space-y-2 text-base">
          <div className="flex justify-between gap-2"><dt className="text-gray-500">Verwendungszweck</dt><dd className="text-right font-medium"><button onClick={() => copy(invoice.nummer, 'Verwendungszweck')} title="Verwendungszweck kopieren" className="text-right"><span className="mr-1 text-blue-600">⧉</span>{invoice.nummer}</button></dd></div>
          <div className="flex justify-between gap-2"><dt className="text-gray-500">Betrag</dt><dd className="text-right font-medium"><button onClick={() => copy(String(Number(invoice.summe).toFixed(2)).replace('.', ','), 'Betrag')} title="Betrag kopieren" className="text-right"><span className="mr-1 text-blue-600">⧉</span>{formatGermanDecimal(Number(invoice.summe))}</button></dd></div>
          <div className="flex justify-between gap-2"><dt className="text-gray-500">Datum</dt><dd className="font-medium">{formatDateISO(invoice.datum)}</dd></div>
          <div className="flex justify-between gap-2"><dt className="text-gray-500">Fällig</dt><dd className="font-medium">{formatDateISO(invoice.faelligkeit)}</dd></div>
          {invoice.iban && <div className="flex justify-between gap-2"><dt className="text-gray-500">IBAN</dt><dd className="text-right font-medium"><button onClick={() => copy(invoice.iban, 'IBAN')} title="IBAN kopieren" className="text-right"><span className="mr-1 text-blue-600">⧉</span>{formatIBAN(invoice.iban)}</button></dd></div>}
        </dl>
        <div className="mt-3 space-y-2">
          {(['PKV', 'Beihilfe', 'Bezahlt'] as InvoiceStatus[]).map((s) => (
            <label key={s} className="flex items-center justify-between rounded-lg bg-gray-50 px-3 py-2 dark:bg-gray-800">
              <span>{s}</span>
              <input type="checkbox" checked={invoice.status.includes(s)} onChange={() => onToggle(invoice, s)} className="h-5 w-5" />
            </label>
          ))}
        </div>
      </div>

      {qrUrl ? (
        <div className="rounded-2xl border border-gray-200 bg-white p-4 text-center dark:border-gray-800 dark:bg-gray-900">
          <img src={qrUrl} alt="GiroCode QR" className="qr-sharp mx-auto h-52 w-52 rounded-lg bg-white p-2" />
          <p className="mt-2 text-xs text-gray-500">Mit Banking-App scannen</p>
          {invoice.iban && <p className="text-xs text-gray-400">{formatIBAN(invoice.iban)}</p>}
        </div>
      ) : (
        <p className="rounded-2xl border border-gray-200 p-3 text-center text-sm text-gray-500 dark:border-gray-800">Kein QR-Code möglich (Name, gültige IBAN und Betrag nötig).</p>
      )}

      {imgUrl && <img src={imgUrl} alt="Rechnung" className="max-h-96 w-full rounded-2xl border border-gray-200 object-contain dark:border-gray-800" />}
      {pdfUrl && <a href={pdfUrl} target="_blank" rel="noreferrer" className="block rounded-2xl border border-gray-200 bg-white p-4 text-center text-blue-600 dark:border-gray-800 dark:bg-gray-900">PDF öffnen ({invoice.pdfName || 'Anhang'})</a>}
    </div>
  )
}

function StatsView({ invoices }: { invoices: Invoice[] }) {
  const paid = invoices.filter((r) => r.status.includes('Bezahlt'))
  const total = paid.reduce((s, r) => s + (Number(r.summe) || 0), 0)
  const byYear = new Map<string, { sum: number; count: number }>()
  for (const r of paid) {
    const y = (r.datum || '').slice(0, 4) || 'ohne Jahr'
    const e = byYear.get(y) ?? { sum: 0, count: 0 }
    e.sum += Number(r.summe) || 0
    e.count++
    byYear.set(y, e)
  }
  // Top 10 Empfänger nach überwiesener Summe (nur bezahlte)
  const byRecipient = new Map<string, { sum: number; count: number }>()
  for (const r of paid) {
    const name = (r.name || 'Unbenannt').trim() || 'Unbenannt'
    const e = byRecipient.get(name) ?? { sum: 0, count: 0 }
    e.sum += Number(r.summe) || 0
    e.count++
    byRecipient.set(name, e)
  }
  const top10 = [...byRecipient.entries()]
    .sort((a, b) => b[1].sum - a[1].sum)
    .slice(0, 10)
  const maxTop = top10.length > 0 ? top10[0][1].sum : 0
  return (
    <div className="space-y-3">
      <div className="rounded-2xl border border-gray-200 bg-white p-4 dark:border-gray-800 dark:bg-gray-900">
        <p className="text-sm text-gray-500">Summe bezahlt ({paid.length})</p>
        <p className="text-2xl font-semibold tabular-nums">{formatGermanDecimal(total)}</p>
      </div>
      {top10.length > 0 && (
        <div className="overflow-hidden rounded-2xl border border-gray-200 bg-white dark:border-gray-800 dark:bg-gray-900">
          <h3 className="px-4 pb-1 pt-3 text-sm font-semibold text-gray-500">Top 10 Empfänger</h3>
          <ul className="divide-y divide-gray-100 dark:divide-gray-800">
            {top10.map(([name, v], i) => (
              <li key={name} className="px-4 py-2.5">
                <div className="flex items-baseline gap-2">
                  <span className="w-6 shrink-0 text-sm font-semibold tabular-nums text-gray-400">{i + 1}.</span>
                  <span className="min-w-0 flex-1 truncate text-[15px] font-medium">{name}</span>
                  <span className="shrink-0 text-[15px] font-semibold tabular-nums">
                    {formatGermanDecimal(v.sum)}
                  </span>
                </div>
                <div className="mt-1.5 flex items-center gap-2 pl-8">
                  <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-gray-100 dark:bg-gray-800">
                    <div
                      className="h-full rounded-full bg-blue-500"
                      style={{ width: `${maxTop > 0 ? Math.max(4, Math.round((v.sum / maxTop) * 100)) : 0}%` }}
                    />
                  </div>
                  <span className="shrink-0 text-xs tabular-nums text-gray-400">
                    {v.count} {v.count === 1 ? 'Rechnung' : 'Rechnungen'}
                  </span>
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}
      {[...byYear.entries()].sort((a, b) => b[0].localeCompare(a[0])).map(([y, v]) => (
        <div key={y} className="flex justify-between rounded-2xl border border-gray-200 bg-white p-4 dark:border-gray-800 dark:bg-gray-900">
          <span className="font-medium">{y}</span>
          <span className="tabular-nums">{formatGermanDecimal(v.sum)} <span className="text-xs text-gray-500">({v.count})</span></span>
        </div>
      ))}
      {paid.length === 0 && <p className="py-10 text-center text-gray-500">Noch keine bezahlten Rechnungen.</p>}
    </div>
  )
}

function LoginView() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [mode, setMode] = useState<'link' | 'password'>('link')
  const [sent, setSent] = useState(false)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  function validEmail() {
    return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())
  }

  async function send() {
    setError('')
    if (!validEmail()) {
      setError('Bitte eine gültige E-Mail-Adresse eingeben.')
      return
    }
    setBusy(true)
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: { emailRedirectTo: window.location.origin + import.meta.env.BASE_URL },
    })
    setBusy(false)
    if (error) setError(rateLimitHint(error.message))
    else setSent(true)
  }

  async function loginPassword() {
    setError('')
    if (!validEmail() || !password) {
      setError('Bitte E-Mail und Passwort eingeben.')
      return
    }
    setBusy(true)
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
    setBusy(false)
    if (error) setError(rateLimitHint(error.message))
    // Erfolg: onAuthStateChange schaltet die App um
  }

  return (
    <div className="rounded-2xl border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-900">
      <h2 className="text-lg font-semibold">Anmelden</h2>
      <div className="mt-2 flex gap-1 rounded-full bg-gray-100 p-1 text-sm dark:bg-gray-800">
        {(['link', 'password'] as const).map((m) => (
          <button
            key={m}
            onClick={() => { setMode(m); setError(''); setSent(false) }}
            className={`flex-1 rounded-full py-1.5 ${mode === m ? 'bg-white font-semibold shadow-sm dark:bg-gray-900' : 'text-gray-500'}`}
          >
            {m === 'link' ? 'Per E-Mail-Link' : 'Mit Passwort'}
          </button>
        ))}
      </div>
      {sent && mode === 'link' ? (
        <p className="mt-3 text-[15px]">
          Link gesendet an <strong>{email}</strong>. Bitte im <strong>selben Browser</strong> auf dem Gerät öffnen, auf dem du dich anmeldest – danach ist der Sync auf allen Geräten aktiv.
        </p>
      ) : (
        <>
          <p className="mt-2 text-sm text-gray-500">
            {mode === 'link'
              ? 'Du erhältst einen Login-Link per E-Mail (kein Passwort nötig). Auf jedem Gerät einmal anmelden.'
              : 'Für Geräte ohne Mail-Empfang – das Passwort legst du einmalig im Konto-Tab fest.'}
          </p>
          <div className="mt-3 space-y-2">
            <input
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') mode === 'link' ? send() : loginPassword() }}
              placeholder="E-Mail-Adresse"
              inputMode="email"
              autoComplete="email"
              className="w-full rounded-lg bg-gray-50 px-3 py-2 text-base outline-none placeholder:text-gray-400 dark:bg-gray-800"
            />
            {mode === 'password' && (
              <input
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') loginPassword() }}
                placeholder="Passwort"
                type="password"
                autoComplete="current-password"
                className="w-full rounded-lg bg-gray-50 px-3 py-2 text-base outline-none placeholder:text-gray-400 dark:bg-gray-800"
              />
            )}
            <button
              onClick={mode === 'link' ? send : loginPassword}
              disabled={busy}
              className="w-full rounded-lg bg-black px-4 py-2 text-sm font-semibold text-white disabled:opacity-40 dark:bg-white dark:text-black"
            >
              {mode === 'link' ? 'Link senden' : 'Anmelden'}
            </button>
          </div>
          {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
        </>
      )}
    </div>
  )
}

/** Verständlichere Meldung bei Supabase-Limits. */
function rateLimitHint(message: string): string {
  if (/rate ?limit/i.test(message)) {
    return 'E-Mail-Limit erreicht (Supabase Free erlaubt nur wenige Mails pro Stunde). Bitte ca. 1 Stunde warten – oder per Passwort anmelden.'
  }
  return message
}

function formatSyncTime(iso: string | null): string {
  if (!iso) return 'noch nie'
  const d = new Date(iso)
  return new Intl.DateTimeFormat('de-DE', { dateStyle: 'short', timeStyle: 'short' }).format(d)
}

function BackupView({ email, syncState }: { email: string; syncState: SyncState }) {
  const [msg, setMsg] = useState('')
  const [syncing, setSyncing] = useState(false)
  const [pw, setPw] = useState('')
  const [pwMsg, setPwMsg] = useState('')
  async function onImport(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0]
    if (!f) return
    try {
      const r = await importBackupFile(f)
      setMsg(`Import: ${r.imported} neu, ${r.updated} aktualisiert, ${r.skipped} übersprungen.`)
      scheduleSync()
    } catch (err) {
      setMsg(`Fehler: ${(err as Error).message}`)
    }
    e.target.value = ''
  }
  async function logout() {
    await supabase.auth.signOut()
  }
  return (
    <div className="space-y-3">
      <div className="rounded-2xl border border-gray-200 bg-white p-4 dark:border-gray-800 dark:bg-gray-900">
        <h2 className="font-bold">Konto & Sync</h2>
        <p className="mt-1 truncate text-sm text-gray-500">{email}</p>
        <p className="mt-2 text-sm">
          {syncState.kind === 'syncing' && '🔄 Synchronisiere …'}
          {syncState.kind === 'idle' && `✓ Zuletzt synchronisiert: ${formatSyncTime(syncState.at)}`}
          {syncState.kind === 'error' && `⚠ Sync-Fehler: ${syncState.message}`}
        </p>
        <div className="mt-3 flex gap-2">
          <button
            onClick={async () => { setSyncing(true); await syncNow(); setSyncing(false) }}
            disabled={syncing || syncState.kind === 'syncing'}
            className="rounded-lg bg-black px-4 py-2 text-sm font-semibold text-white disabled:opacity-40 dark:bg-white dark:text-black"
          >
            Jetzt syncen
          </button>
          <button onClick={logout} className="rounded-lg bg-gray-200 px-4 py-2 text-sm dark:bg-gray-800">
            Abmelden
          </button>
        </div>
        <div className="mt-3 border-t border-gray-100 pt-3 dark:border-gray-800">
          <p className="text-sm font-medium">Passwort für Login ohne E-Mail</p>
          <div className="mt-1.5 flex gap-2">
            <input
              value={pw}
              onChange={(e) => { setPw(e.target.value); setPwMsg('') }}
              placeholder="Neues Passwort (min. 6 Zeichen)"
              type="password"
              autoComplete="new-password"
              className="w-full rounded-lg bg-gray-50 px-3 py-2 text-sm outline-none placeholder:text-gray-400 dark:bg-gray-800"
            />
            <button
              onClick={async () => {
                setPwMsg('')
                if (pw.length < 6) { setPwMsg('Mindestens 6 Zeichen nötig.'); return }
                const { error } = await supabase.auth.updateUser({ password: pw })
                if (error) setPwMsg(`Fehler: ${error.message}`)
                else { setPwMsg('✓ Gespeichert – ab jetzt geht auch Login mit Passwort.'); setPw('') }
              }}
              className="shrink-0 rounded-lg bg-gray-200 px-4 py-2 text-sm dark:bg-gray-800"
            >
              Speichern
            </button>
          </div>
          {pwMsg && <p className="mt-1.5 text-sm text-gray-600 dark:text-gray-300">{pwMsg}</p>}
        </div>
      </div>
      <div className="rounded-2xl border border-gray-200 bg-white p-4 dark:border-gray-800 dark:bg-gray-900">
        <h2 className="font-bold">Backup v2</h2>
        <p className="text-sm text-gray-500">Export als JSON-Download. Import versteht v2 und alte iOS-Backups (v1).</p>
        <div className="mt-3 flex gap-2">
          <button onClick={exportBackupV2} className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white">Exportieren</button>
          <label className="cursor-pointer rounded-lg bg-gray-200 px-4 py-2 text-sm dark:bg-gray-800">
            Importieren
            <input type="file" accept="application/json,.json" className="hidden" onChange={onImport} />
          </label>
        </div>
        {msg && <p className="mt-2 text-sm">{msg}</p>}
      </div>
      <p className="text-xs text-gray-500">Tipp: Alte Datei <code>Rechnungen_Backup_*.json</code> vom iPhone hier importieren – IDs werden neu vergeben, Duplikate über Verwendungszweck erkannt.</p>
    </div>
  )
}

function InvoiceForm({ initial, onClose, onSaved }: {
  initial: Invoice | null
  onClose: () => void
  onSaved: (id: string) => void
}) {
  const [name, setName] = useState(initial?.name ?? '')
  const [nummer, setNummer] = useState(initial?.nummer ?? '')
  const [summe, setSumme] = useState(initial ? initial.summe.replace('.', ',') : '')
  const [datum, setDatum] = useState(initial?.datum ?? todayISO())
  const [faelligkeit, setFaelligkeit] = useState(initial?.faelligkeit ?? todayISO())
  const [iban, setIban] = useState(initial?.iban ?? '')
  const [status, setStatus] = useState<InvoiceStatus[]>(initial?.status ?? [])
  const [bild, setBild] = useState<File | null>(null)
  const [pdf, setPdf] = useState<File | null>(null)
  const [bildRemoved, setBildRemoved] = useState(false)
  const [pdfRemoved, setPdfRemoved] = useState(false)
  const [error, setError] = useState('')

  const parsed = parseGermanDecimal(summe)
  const valid = name.trim() !== '' && nummer.trim() !== '' && parsed !== null
  // Anhang, der nach dem Speichern bestehen bleibt (neu gewählt oder vorhanden)
  const keepBild = bildRemoved ? null : bild ?? initial?.bild
  const keepPdf = pdfRemoved ? null : pdf ?? initial?.pdf
  const attachmentsTouched = bild !== null || pdf !== null || bildRemoved || pdfRemoved

  function toggle(s: InvoiceStatus) {
    setStatus((prev) => (prev.includes(s) ? prev.filter((x) => x !== s) : [...prev, s]))
  }

  async function save() {
    if (!valid || parsed === null) { setError('Name, Verwendungszweck und gültiger Betrag sind Pflicht.'); return }
    const now = nowISO()
    const id = initial?.id ?? newId()
    const rec: Invoice = {
      id,
      name: name.trim(),
      nummer: nummer.trim(),
      summe: toStorageString(parsed),
      datum,
      faelligkeit,
      status,
      iban: iban.replace(/\s/g, '').toUpperCase(),
      createdAt: initial?.createdAt ?? now,
      updatedAt: now,
    }
    // Anhänge nur setzen, wenn sie bestehen bleiben – so verschwinden gelöschte
    // Anhänge wirklich aus dem Datensatz (und werden remote mit gelöscht).
    if (keepBild) {
      rec.bild = keepBild
      rec.bildName = bild?.name ?? initial?.bildName
      rec.bildType = bild?.type ?? initial?.bildType
    }
    if (keepPdf) {
      rec.pdf = keepPdf
      rec.pdfName = pdf?.name ?? initial?.pdfName
    }
    // Nach Anhang-Änderung den Sync erneut anstoßen (auch wenn updatedAt älter ist).
    if (attachmentsTouched) rec.syncPending = true
    else if (initial?.syncPending) rec.syncPending = initial.syncPending
    await db.invoices.put(rec)
    onSaved(id)
    scheduleSync()
  }

  return (
    <div className="fixed inset-0 z-20 overflow-y-auto bg-black/30 p-4 backdrop-blur-sm">
      <div className="mx-auto max-w-lg rounded-3xl border border-white/40 bg-white/60 p-4 shadow-[0_8px_40px_rgba(0,0,0,0.15)] backdrop-blur-2xl backdrop-saturate-150 dark:border-white/10 dark:bg-gray-900/60">
        <h2 className="text-lg font-bold">{initial ? 'Bearbeiten' : 'Neue Rechnung'}</h2>
        <div className="mt-3 space-y-2 text-base">
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Name *" className="w-full rounded-lg bg-white/70 px-3 py-2 text-base outline-none placeholder:text-gray-400 focus:bg-white/80 dark:bg-white/15 dark:focus:bg-white/15" />
          <input value={nummer} onChange={(e) => setNummer(e.target.value)} placeholder="Verwendungszweck *" className="w-full rounded-lg bg-white/70 px-3 py-2 text-base outline-none placeholder:text-gray-400 focus:bg-white/80 dark:bg-white/15 dark:focus:bg-white/15" />
          <input value={summe} onChange={(e) => setSumme(e.target.value)} placeholder="Betrag (€), z.B. 125,50 *" inputMode="decimal" className="w-full rounded-lg bg-white/70 px-3 py-2 text-base outline-none placeholder:text-gray-400 focus:bg-white/80 dark:bg-white/15 dark:focus:bg-white/15" />
          <input value={iban} onChange={(e) => setIban(e.target.value.toUpperCase())} placeholder="IBAN (optional)" className="w-full rounded-lg bg-white/70 px-3 py-2 text-base outline-none placeholder:text-gray-400 focus:bg-white/80 dark:bg-white/15 dark:focus:bg-white/15" />
          <div className="flex items-center justify-between gap-2 rounded-lg bg-white/70 px-3 py-2 dark:bg-white/15">
            <span>Datum</span>
            <input type="date" value={datum} onChange={(e) => setDatum(e.target.value)} className="bg-transparent text-base outline-none" />
          </div>
          <div className="flex items-center justify-between gap-2 rounded-lg bg-white/70 px-3 py-2 dark:bg-white/15">
            <span>Fällig</span>
            <input type="date" value={faelligkeit} onChange={(e) => setFaelligkeit(e.target.value)} className="bg-transparent text-base outline-none" />
          </div>
          <div className="space-y-2">
            {(['PKV', 'Beihilfe', 'Bezahlt'] as InvoiceStatus[]).map((s) => (
              <label key={s} className="flex items-center justify-between rounded-lg bg-white/70 px-3 py-2 dark:bg-white/15">
                <span>{s}</span>
                <input type="checkbox" checked={status.includes(s)} onChange={() => toggle(s)} className="h-5 w-5" />
              </label>
            ))}
          </div>
          <div className="flex gap-2 text-sm">
            <label className="flex-1 cursor-pointer rounded-lg bg-white/70 p-2 text-center dark:bg-white/15">Foto {keepBild ? '✓' : ''}<input type="file" accept="image/*" className="hidden" onChange={(e) => { setBild(e.target.files?.[0] ?? null); setBildRemoved(false) }} /></label>
            <label className="flex-1 cursor-pointer rounded-lg bg-white/70 p-2 text-center dark:bg-white/15">PDF {keepPdf ? '✓' : ''}<input type="file" accept="application/pdf" className="hidden" onChange={(e) => { setPdf(e.target.files?.[0] ?? null); setPdfRemoved(false) }} /></label>
          </div>
          {(keepBild || keepPdf || bildRemoved || pdfRemoved) && (
            <div className="flex flex-wrap gap-2 text-xs">
              {keepBild && (
                <button onClick={() => { setBild(null); setBildRemoved(true) }} className="rounded-lg bg-red-50 px-3 py-1.5 text-red-600 dark:bg-red-950/50 dark:text-red-400">Foto entfernen</button>
              )}
              {keepPdf && (
                <button onClick={() => { setPdf(null); setPdfRemoved(true) }} className="rounded-lg bg-red-50 px-3 py-1.5 text-red-600 dark:bg-red-950/50 dark:text-red-400">PDF entfernen</button>
              )}
              {bildRemoved && initial?.bild && <span className="px-1 py-1.5 text-gray-500">Foto wird beim Speichern gelöscht</span>}
              {pdfRemoved && initial?.pdf && <span className="px-1 py-1.5 text-gray-500">PDF wird beim Speichern gelöscht</span>}
            </div>
          )}
          {error && <p className="text-sm text-red-600">{error}</p>}
          {!valid && <p className="text-xs text-gray-500">* Pflichtfelder</p>}
        </div>
        <div className="mt-4 flex gap-2">
          <button onClick={onClose} className="flex-1 rounded-lg bg-gray-200 py-2 dark:bg-gray-800">Abbrechen</button>
          <button onClick={save} disabled={!valid} className="flex-1 rounded-lg bg-blue-600 py-2 font-semibold text-white disabled:opacity-40">Speichern</button>
        </div>
      </div>
    </div>
  )
}
