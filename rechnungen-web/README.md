# Rechnungen Web

Statische PWA (React + TypeScript + Tailwind + Dexie/IndexedDB), hostbar auf GitHub Pages.
Das Xcode-Projekt bleibt unangetastet daneben bestehen.

## Start

```bash
cd rechnungen-web
npm install
npm run dev     # http://localhost:5173
npm test        # Vitest: Decimal/IBAN/GiroCode/v1-Migration
npm run build   # dist/
```

## Funktionen (MVP)

- Liste mit Suche, unbezahlte zuerst (Fälligkeit aufsteigend), bezahlte danach absteigend
- Detail mit PKV/Beihilfe/Bezahlt-Toggles, Copy-Buttons, Bild/PDF-Anhang
- GiroCode-QR (EPC069-12) nach Name + gültiger IBAN (mod-97) + Betrag
- Statistik bezahlter Rechnungen pro Jahr
- Backup v2 (JSON-Download) + Import von v2 **und** alten iOS-Backups v1 (`Rechnungen_Backup_*.json`)

## Backup-Formate

- **v2** (`version: "2.0"`): mit `id` (UUID), `status` als Array, Timestamps, Blobs als base64.
- **v1** (iOS): `status` als Komma-String inkl. Alt-Werten (`PKV eingereicht`). Beim Import wird gemappt, IDs neu vergeben, Duplikate über `nummer` erkannt (Report: importiert/aktualisiert/übersprungen).

## Deploy

Push auf `main` baut via `.github/workflows/pages.yml` und deployed `rechnungen-web/dist` auf Pages:
`https://<user>.github.io/Rechnungen/`
(`base: '/Rechnungen/'` in `vite.config.ts` – bei anderem Repo-Namen anpassen.)

## Sync (Supabase)

* IndexedDB bleibt lokale Wahrheit (offline-fähig). `src/lib/sync.ts`: Push bei Änderung (entprellt, 3 s), Pull bei Login, alle 60 s und bei Tab-Rückkehr. Konflikt = neuere `updatedAt` gewinnt, Löschen via Tombstones/Soft-Delete.
* Anhänge liegen in Supabase Storage (Bucket `attachments`, Pfad `<user-id>/<rechnungs-id>/bild|pdf`), privat per RLS.
* Robust: Fehler einzelner Zeilen/Anhänge brechen den Lauf nicht ab – sie werden gesammelt im Sync-Status gemeldet und über das lokale Flag `syncPending` beim nächsten Lauf erneut versucht (auch nach Weiterrücken des Sync-Zeitpunkts). Postgres-Zeitstempel (`…+00:00`) werden für den Vergleich auf ISO-UTC normalisiert. Schlägt ein `upsert` fehl, wird der Pfad nicht überschrieben.
* Anhang-Upload als Multipart mit benanntem Feld `file` (+ `contentType`): Ein `Blob` direkt an storage-js wird mit leerem Feldnamen gesendet, der Storage-Server antwortet dann mit „No content provided“. Fallback: Rohkörper (ArrayBuffer). Nach Änderungen an der Upload-Logik wird über `SYNC_REVISION` in `sync.ts` einmalig alles erneut gepusht.
* Anhänge löschen: im Bearbeiten-Dialog per „Foto entfernen“/„PDF entfernen“. Lokal verschwindet der Anhang, im Storage wird das Objekt gelöscht und andere Geräte entfernen ihre Kopie beim nächsten Pull (ebenso beim Löschen einer Rechnung).
* Kopieren („Kopieren“ und „⧉“ an Feldern) liefert immer Klartext: `toPlainText()` entfernt Steuerzeichen, Zero-Width-/Bidi-/BOM-Zeichen und ersetzt Sonder-Leerzeichen.
* Anmeldung per Magic-Link (Supabase Auth). Login-Screen erscheint automatisch ohne Session; Konto/Sync-Status + „Jetzt syncen“ im Backup-Tab.
* Umgebungsvariablen (`VITE_SUPABASE_URL`, `VITE_SUPABASE_KEY`) via `.env.local` – Fallback-Werte sind in `src/lib/supabase.ts` eingebaut, sodass auch der Pages-Build ohne Secrets läuft.
## Hinweise (Sync-Details)

- Einmal-Migration: nach erstem Login werden bestehende lokale Daten automatisch hochgeladen (IDs bleiben stabil).
- DB-Schema + RLS-Policies siehe Plan-Phase (Tabelle `invoices`, Bucket `attachments`, alles an `auth.uid()` gebunden).
