import Foundation
import WatchConnectivity
import UIKit

class ConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = ConnectivityManager()
    
    @Published var isReachable = false
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func sendInvoiceData(title: String, qrCodeData: Data) {
        guard WCSession.default.activationState == .activated else { return }
        
        let message: [String: Any] = [
            "title": title,
            "qrCodeData": qrCodeData
        ]
        
        if qrCodeData.count < GiroCodeGenerator.maxWatchPayloadBytes {
            // Update Application Context (background update)
            do {
                try WCSession.default.updateApplicationContext(message)
            } catch {
                print("ApplicationContext fehlgeschlagen, nutze transferUserInfo: \(error.localizedDescription)")
                WCSession.default.transferUserInfo(message)
            }
        } else {
            // Zu groß für Application Context (~65 KB Limit) → queued Transfer
            WCSession.default.transferUserInfo(message)
        }
        
        // Also try sending immediate message if reachable
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: { error in
                print("Error sending message: \(error.localizedDescription)")
            })
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {}
    
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
