import SwiftUI

struct DevConsoleView: View {
    @ObservedObject var viewModel: LoginViewModel
    var onDismiss: (() -> Void)?
    @State private var codeInput: String = ""

    private var stateLabel: String {
        switch viewModel.state {
        case .idle, .enteringPhone: return "Ready"
        case .awaitingSilentAuth: return "Verifying silently…"
        case .silentAuthSucceeded: return "Silent Auth succeeded"
        case .submittingCode: return "Checking code…"
        case .enteringSmsCode: return "Waiting for SMS code…"
        case .enteringVoiceCode: return "Waiting for voice code…"
        case .verified: return "Verified"
        case .failed: return "Failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(VonageBrand.gray2)
            ChannelTracker(viewModel: viewModel)
            Divider().background(VonageBrand.gray2)
            logStream
            Divider().background(VonageBrand.gray2)
            codeEntry
        }
        .background(Color(.systemBackground))
        .onChange(of: viewModel.state) { _ in codeInput = "" }
    }

    private var header: some View {
        HStack {
            Text(stateLabel)
                .font(.headline)
                .foregroundColor(VonageBrand.plum)
            if viewModel.state == .verified {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(VonageBrand.success)
            }
            Spacer()
            Button("Hide") { onDismiss?() }
                .font(.subheadline)
                .foregroundColor(VonageBrand.purple)
        }
        .padding()
    }

    // MARK: - Grouped log stream

    private var logStream: some View {
        Group {
            if viewModel.devLogs.isEmpty {
                VStack {
                    Spacer()
                    Text("No events yet.\nStart a verification to watch it unfold.")
                        .font(.callout)
                        .foregroundColor(VonageBrand.gray4)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                            ForEach(orderedStages, id: \.self) { stage in
                                StageHeader(stage: stage, outcome: outcome(for: stage))
                                ForEach(events(in: stage)) { event in
                                    LogEventRow(event: event).id(event.id)
                                    Divider().background(VonageBrand.gray1)
                                }
                            }
                        }
                    }
                    .onChange(of: viewModel.devLogs.count) { _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.devLogs.last?.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    /// Stages that currently have at least one event, in flow order.
    private var orderedStages: [LogStage] {
        LogStage.allCases.filter { stage in
            viewModel.devLogs.contains { $0.stage == stage }
        }
    }

    private func events(in stage: LogStage) -> [LogEvent] {
        viewModel.devLogs.filter { $0.stage == stage }
    }

    private func outcome(for stage: LogStage) -> StageOutcome {
        StageOutcome.derive(stage: stage, path: viewModel.path, state: viewModel.state)
    }

    // MARK: - Code entry

    @ViewBuilder
    private var codeEntry: some View {
        if case .enteringSmsCode = viewModel.state {
            codePanel(label: "SMS code", accent: VonageBrand.magenta, showFallback: true, caption: nil)
        } else if case .enteringVoiceCode = viewModel.state {
            codePanel(label: "Voice code", accent: VonageBrand.orange, showFallback: false,
                      caption: "Check your phone — we're calling you now")
        }
    }

    private func codePanel(label: String, accent: Color, showFallback: Bool, caption: String?) -> some View {
        VStack(spacing: 12) {
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundColor(VonageBrand.gray4)
            }

            TextField(label, text: $codeInput)
                .keyboardType(.numberPad)
                .padding()
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(VonageBrand.gray3, lineWidth: 1))

            Button(action: {
                viewModel.submitCode(codeInput)
                codeInput = ""
            }) {
                Text("Verify")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(VonageBrand.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(codeInput.isEmpty)
            .opacity(codeInput.isEmpty ? 0.5 : 1)

            if showFallback {
                Button("Didn't get it? Try a call instead") {
                    viewModel.triggerFallback()
                }
                .font(.subheadline)
                .foregroundColor(VonageBrand.purple)
            }
        }
        .padding()
    }
}

// MARK: - Channel tracker

private struct ChannelTracker: View {
    @ObservedObject var viewModel: LoginViewModel

    private let stages: [LogStage] = [.silentAuth, .sms, .voice]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(stages, id: \.self) { stage in
                let outcome = StageOutcome.derive(stage: stage, path: viewModel.path, state: viewModel.state)
                segment(stage, outcome)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func segment(_ stage: LogStage, _ outcome: StageOutcome) -> some View {
        let accent = StageStyle.accent(for: stage)
        let active = outcome == .active
        return HStack(spacing: 4) {
            Text(outcome.glyph)
            Text(stage.title.uppercased())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(.caption2, design: .monospaced))
        .tracking(0.5)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(active ? accent : (outcome == .succeeded ? VonageBrand.success : VonageBrand.gray1))
        .foregroundColor(active || outcome == .succeeded ? .white : VonageBrand.gray5)
        .cornerRadius(6)
    }
}

// MARK: - Stage header

private struct StageHeader: View {
    let stage: LogStage
    let outcome: StageOutcome

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(StageStyle.accent(for: stage))
                .frame(width: 18, height: 18)
                .overlay(
                    Text("\(max(0, stage.rawValue))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                )
                .opacity(stage == .request || stage == .result ? 0 : 1)
                .frame(width: stage == .request || stage == .result ? 0 : 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(stage.title.uppercased()).vonageEyebrow()
                Text(stage.blurb)
                    .font(.caption2)
                    .foregroundColor(VonageBrand.gray4)
            }

            Spacer()

            if let text = outcome.label {
                Text(text)
                    .font(.caption2)
                    .foregroundColor(outcome.labelColor)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(StageStyle.accent(for: stage).opacity(0.06))
    }
}

// MARK: - Stage outcome

enum StageOutcome: Equatable {
    case fellThrough   // tried, didn't complete → moved on
    case active        // currently in progress
    case succeeded     // completed the verification here
    case pending       // not reached (yet / at all)

    var glyph: String {
        switch self {
        case .fellThrough: return "✕"
        case .active: return "●"
        case .succeeded: return "✓"
        case .pending: return "○"
        }
    }

    var label: String? {
        switch self {
        case .fellThrough: return "fell through"
        case .active: return "in progress"
        case .succeeded: return "verified here"
        case .pending: return nil
        }
    }

    var labelColor: Color {
        switch self {
        case .fellThrough: return VonageBrand.gray4
        case .active: return VonageBrand.purple
        case .succeeded: return VonageBrand.success
        case .pending: return VonageBrand.gray4
        }
    }

    /// Derive a channel stage's outcome from the current path + state.
    static func derive(stage: LogStage, path: LoginViewModel.Path, state: VerificationState) -> StageOutcome {
        let rank: (LogStage) -> Int = { s in
            switch s {
            case .silentAuth: return 0
            case .sms: return 1
            case .voice: return 2
            default: return -1
            }
        }
        let stageRank = rank(stage)
        guard stageRank >= 0 else { return .pending } // request/result aren't channel stages

        let currentRank: Int = {
            switch path {
            case .silentAuth: return 0
            case .sms: return 1
            case .voice: return 2
            }
        }()

        if state == .verified {
            if stageRank == currentRank { return .succeeded }
            return stageRank < currentRank ? .fellThrough : .pending
        }
        if stageRank < currentRank { return .fellThrough }
        if stageRank == currentRank { return .active }
        return .pending
    }
}

#Preview {
    let vm = LoginViewModel()
    return DevConsoleView(viewModel: vm, onDismiss: {})
}
