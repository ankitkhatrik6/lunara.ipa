import SwiftUI

struct ContentView: View {
    @AppStorage("lunaraHasOnboarded") private var hasOnboarded = false
    @State private var showLaunchOverlay = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if hasOnboarded {
                RootView()
                    .transition(.opacity)
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        hasOnboarded = true
                    }
                }
                .transition(.opacity)
            }

            if showLaunchOverlay {
                LaunchSplashOverlay {
                    withAnimation(.easeOut(duration: 0.42)) {
                        showLaunchOverlay = false
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }
}
