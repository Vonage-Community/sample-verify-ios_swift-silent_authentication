import SwiftUI

struct VerifiedView: View {
    @ObservedObject var viewModel: LoginViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(VonageBrand.purple)

            Text("You're verified")
                .font(.title)
                .fontWeight(.medium)
                .foregroundColor(VonageBrand.plum)

            Text("Your phone number has been successfully verified.")
                .font(.body)
                .foregroundColor(VonageBrand.gray4)
                .multilineTextAlignment(.center)

            Spacer()

            Button(action: {
                viewModel.signOut()
            }) {
                Text("Sign out")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(VonageBrand.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            Text("Powered by Vonage")
                .font(.caption2)
                .foregroundColor(VonageBrand.gray4)
        }
        .frame(maxWidth: 440)
        .padding()
    }
}

#Preview {
    VerifiedView(viewModel: LoginViewModel(service: MockPreviewService()))
}
