import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = LoginViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular && viewModel.devModeEnabled {
            // iPad with Dev Mode: side-by-side layout
            NavigationStack {
                HStack(spacing: 0) {
                    mainContent
                        .navigationTitle(navigationTitle)
                    Divider()
                    DevConsoleView(viewModel: viewModel, onDismiss: { viewModel.devModeEnabled = false })
                        .frame(minWidth: 280, maxWidth: 360)
                }
            }
        } else {
            // iPhone: full-width content + fullScreenCover for Dev Mode during verification
            NavigationStack {
                mainContent
                    .navigationTitle(navigationTitle)
                    .fullScreenCover(isPresented: Binding(
                        get: { viewModel.devModeEnabled && !viewModel.state.isIdle },
                        set: { if !$0 { viewModel.devModeEnabled = false } }
                    )) {
                        DevConsoleView(viewModel: viewModel, onDismiss: { viewModel.devModeEnabled = false })
                    }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.state == .verified {
            VerifiedView(viewModel: viewModel)
        } else {
            LoginView(viewModel: viewModel)
        }
    }

    private var navigationTitle: String {
        viewModel.state == .verified ? "Verified" : "Silent Authentication"
    }
}

#Preview {
    ContentView()
}
