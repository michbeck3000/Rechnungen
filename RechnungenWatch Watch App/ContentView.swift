import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    
    var body: some View {
        ScrollView {
            VStack {
                if let image = connectivity.qrCodeImage {
                    Text(connectivity.invoiceTitle ?? "Rechnung")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none) // Important for QR codes to stay sharp
                        .scaledToFit()
                        .padding(4)
                        .background(Color.white)
                        .cornerRadius(8)
                    
                    Text("Zum Bezahlen scannen")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                        .padding(.bottom)
                    
                    Text("Keine Rechnung")
                        .font(.headline)
                    
                    Text("Öffne eine Rechnung auf dem iPhone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchConnectivityManager.shared)
}
