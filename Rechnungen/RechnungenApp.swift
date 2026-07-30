//
//  RechnungenApp.swift
//  Rechnungen
//
//  Created by michbeck on 17.04.25.
//

import SwiftUI

// Sprache explizit festlegen
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Sprache auf Deutsch festlegen
        UserDefaults.standard.set(["de-DE"], forKey: "AppleLanguages")
        UserDefaults.standard.set("de_DE", forKey: "AppleLocale")
        return true
    }
}

@main
struct RechnungenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.locale, Locale(identifier: "de_DE"))
        }
    }
}
