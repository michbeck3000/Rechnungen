import SwiftUI
import CoreData

struct StatisticsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Rechnungen.datum, ascending: false)],
        animation: .default
    )
    private var rechnungen: FetchedResults<Rechnungen>

    private var bezahlteRechnungen: [Rechnungen] {
        rechnungen.filter { ($0.status ?? "").contains("Bezahlt") && $0.summe != nil }
    }

    private var gesamtSumme: Decimal {
        bezahlteRechnungen.reduce(Decimal.zero) { $0 + ($1.summe?.decimalValue ?? .zero) }
    }

    private var gruppiertNachJahr: [(jahr: Int, monate: [(monat: Int, summe: Decimal, anzahl: Int)])] {
        var dict: [Int: [Int: (summe: Decimal, anzahl: Int)]] = [:]
        let calendar = Calendar.current

        for r in bezahlteRechnungen {
            guard let datum = r.datum else { continue }
            let jahr = calendar.component(.year, from: datum)
            let monat = calendar.component(.month, from: datum)
            let betrag = r.summe?.decimalValue ?? .zero

            var monate = dict[jahr, default: [:]]
            let aktuell = monate[monat] ?? (summe: .zero, anzahl: 0)
            monate[monat] = (summe: aktuell.summe + betrag, anzahl: aktuell.anzahl + 1)
            dict[jahr] = monate
        }

        return dict.sorted { $0.key > $1.key }.map { jahr, monate in
            (jahr: jahr, monate: monate.sorted { $0.key > $1.key }.map { monat, werte in
                (monat: monat, summe: werte.summe, anzahl: werte.anzahl)
            })
        }
    }

    private var monatsNamen: [Int: String] {
        var names: [Int: String] = [:]
        let symbols = Calendar.current.monthSymbols
        for (index, symbol) in symbols.enumerated() {
            names[index + 1] = symbol
        }
        return names
    }

    var body: some View {
        List {
            if bezahlteRechnungen.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Noch keine bezahlten Rechnungen")
                            .font(.headline)
                        Text("Sobald Rechnungen als \"Bezahlt\" markiert sind, erscheinen hier die Statistiken.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section("Gesamt") {
                    LabeledContent("Summe") {
                        Text(currencyFormatter.string(from: NSDecimalNumber(decimal: gesamtSumme)) ?? "")
                            .bold()
                    }
                    LabeledContent("Rechnungen", value: "\(bezahlteRechnungen.count)")
                }

                ForEach(gruppiertNachJahr, id: \.jahr) { jahrGruppe in
                    Section {
                        let jahressumme = jahrGruppe.monate.reduce(Decimal.zero) { $0 + $1.summe }
                        LabeledContent("Jahressumme") {
                            Text(currencyFormatter.string(from: NSDecimalNumber(decimal: jahressumme)) ?? "")
                                .bold()
                        }

                        ForEach(jahrGruppe.monate, id: \.monat) { monat in
                            LabeledContent(monatsNamen[monat.monat] ?? "Monat \(monat.monat)") {
                                HStack(spacing: 8) {
                                    Text(currencyFormatter.string(from: NSDecimalNumber(decimal: monat.summe)) ?? "")
                                    Text("(\(monat.anzahl))")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                    } header: {
                        Text("\(jahrGruppe.jahr)")
                            .font(.headline)
                    }
                }
            }
        }
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
    }
}
