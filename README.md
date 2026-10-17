# Rechnungen

Web-App (React-PWA) zur privaten Rechnungsverwaltung mit Fokus auf das deutsche Gesundheitswesen (PKV/Beihilfe) – läuft im Browser und synchronisiert per Supabase zwischen den Geräten.

* **App:** <https://michbeck3000.github.io/Rechnungen/> (iPhone: „Zum Home-Bildschirm“, Mac: „Zum Dock hinzufügen“)
* **Code:** [`rechnungen-web/`](rechnungen-web/) – Setup, Datenmodell, Sync und Deployment: siehe [`rechnungen-web/README.md`](rechnungen-web/README.md)
* **Deployment:** GitHub Actions (`.github/workflows/pages.yml`) baut `rechnungen-web/dist` und veröffentlicht es auf GitHub Pages

## Hinweis

Die frühere iOS/SwiftUI-App ist nicht mehr Teil dieses Repos; ihre Commits sind weiterhin in der Git-Historie erhalten. Weiterentwickelt wird nur noch die Web-App.

## Autor

Michael Seyer – michbeck@seyer-carrera.de
