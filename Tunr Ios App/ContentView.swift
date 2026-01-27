import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color.red.ignoresSafeArea()
            Text("Hello iPhone 👋")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.white)
        }
    }
}

#Preview {
    ContentView()
}
