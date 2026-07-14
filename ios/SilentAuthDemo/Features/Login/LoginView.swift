import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel
    @State private var phone: String = ""
    @State private var smsCode: String = ""
    @State private var voiceCode: String = ""

    var body: some View {
        VStack(spacing: 20) {
            contentForState

            Divider()
                .padding(.vertical, 8)

            Toggle("Dev Mode", isOn: $viewModel.devModeEnabled)
                .tint(VonageBrand.purple)
                .padding()

            Text("Powered by Vonage")
                .font(.caption2)
                .foregroundColor(VonageBrand.gray4)
        }
        .frame(maxWidth: 440)
        .padding()
    }

    @ViewBuilder
    private var contentForState: some View {
        switch viewModel.state {
        case .idle, .enteringPhone:
            phoneEntryView

        case .awaitingSilentAuth:
            ProgressView("Verifying silently…")
                .tint(VonageBrand.purple)
                .frame(height: 100)

        case .submittingCode:
            ProgressView("Checking code…")
                .tint(VonageBrand.purple)
                .frame(height: 100)

        case .enteringSmsCode(let requestId):
            codeEntryView(for: "SMS Code", code: $smsCode, requestId: requestId, isFallback: true)

        case .enteringVoiceCode(let requestId):
            codeEntryView(for: "Voice Code", code: $voiceCode, requestId: requestId, isFallback: false)

        case .verified:
            EmptyView()

        case .failed(let message):
            errorView(message: message)

        case .silentAuthSucceeded:
            EmptyView()
        }
    }

    private var phoneEntryView: some View {
        VStack(spacing: 12) {
            // Official "Part of Ericsson" lock-up, rendered as a template so it
            // tints with the brand plum and stays legible in dark mode.
            Image("VonageLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 42)
                .foregroundColor(VonageBrand.plum)
                .padding(.bottom, 8)
                .accessibilityLabel("Vonage, part of Ericsson")

            Text("Sign in with your phone")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(VonageBrand.plum)

            VStack(spacing: 8) {
                Text("This demo application uses the Vonage Verify API to authenticate silently or fall back to traditional 2FA methods.")
                    .font(.subheadline)
                    .foregroundColor(VonageBrand.gray5)
                    .multilineTextAlignment(.center)

                Link("Read the documentation", destination: URL(string: "https://developer.vonage.com/en/verify/overview")!)
                    .font(.subheadline)
                    .foregroundColor(VonageBrand.purple)
            }
            .padding(.bottom, 12)

            TextField("E.164 format: +1234567890", text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .padding()
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(VonageBrand.gray3, lineWidth: 1))

            Button(action: {
                viewModel.submitPhone(phone)
            }) {
                Text("Sign in")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(VonageBrand.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(phone.isEmpty)
            .opacity(phone.isEmpty ? 0.5 : 1)
        }
    }

    private func codeEntryView(for label: String, code: Binding<String>, requestId: String, isFallback: Bool) -> some View {
        VStack(spacing: 12) {
            Text(label)
                .font(.headline)
                .foregroundColor(VonageBrand.plum)

            if !isFallback {
                Text("Check your phone — we're calling you now")
                    .font(.caption)
                    .foregroundColor(VonageBrand.gray4)
            }

            TextField("Enter code", text: code)
                .keyboardType(.numberPad)
                .padding()
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(VonageBrand.gray3, lineWidth: 1))

            Button(action: {
                viewModel.submitCode(code.wrappedValue)
            }) {
                Text("Verify")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(VonageBrand.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(code.wrappedValue.isEmpty)
            .opacity(code.wrappedValue.isEmpty ? 0.5 : 1)

            if isFallback {
                Button(action: {
                    viewModel.triggerFallback()
                }) {
                    Text("Didn't get it? Try a call instead")
                        .foregroundColor(VonageBrand.purple)
                }
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.red)

            Text("Verification failed")
                .font(.headline)
                .foregroundColor(VonageBrand.plum)

            Text(message)
                .font(.caption)
                .foregroundColor(VonageBrand.gray4)
                .multilineTextAlignment(.center)

            Button(action: {
                viewModel.signOut()
                phone = ""
                smsCode = ""
                voiceCode = ""
            }) {
                Text("Try again")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(VonageBrand.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
}

#Preview {
    LoginView(viewModel: LoginViewModel(service: MockPreviewService()))
}

class MockPreviewService: VerificationServiceProtocol {
    func startVerification(phone: String) async throws -> (requestId: String, checkUrl: String?) {
        ("preview-req", nil)
    }

    func performCellularCheck(checkUrl: String) async throws -> CellularCheckResult {
        CellularCheckResult(code: "preview-code", requestId: "preview-req")
    }

    func triggerFallback(requestId: String) async throws {
    }

    func submitCode(requestId: String, code: String) async throws -> Bool {
        true
    }

    func fetchLogs(requestId: String) async throws -> LogsResponse {
        LogsResponse(logs: [], channel: nil)
    }
}
