import SwiftUI
import WatchConnectivity
import Combine
import UIKit

@main
struct RechnungenWatch_Watch_AppApp: App {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity)
        }
    }
}

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    
    @Published var invoiceTitle: String?
    @Published var qrCodeImage: UIImage?
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed: \(error.localizedDescription)")
        }
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        processData(applicationContext)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        processData(message)
    }
    
    private func processData(_ data: [String: Any]) {
        DispatchQueue.main.async {
            if let title = data["title"] as? String {
                self.invoiceTitle = title
            }
            if let imageData = data["qrCodeData"] as? Data, let image = UIImage(data: imageData) {
                self.qrCodeImage = image
            }
        }
    }
}
