import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @State private var showingFullscreen = false
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack {
                    if let image = connectivity.qrCodeImage {
                        Text(connectivity.invoiceTitle ?? "Rechnung")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            showingFullscreen = true
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.none) // Important for QR codes to stay sharp
                                .scaledToFit()
                                .padding(4)
                                .background(Color.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
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
            
            if showingFullscreen, let image = connectivity.qrCodeImage {
                QRCodeFullscreenView(image: image) {
                    showingFullscreen = false
                }
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchConnectivityManager.shared)
}
