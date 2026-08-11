import SwiftUI

struct QRCodeFullscreenView: View {
    let image: UIImage
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .padding(16)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
        .ignoresSafeArea()
    }
}
