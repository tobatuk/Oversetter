import SwiftUI

struct ContentView: View {
    @State private var model = TranslationViewModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    languageBar
                    inputCard
                    actionRow
                    statusView
                    outputCard
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Oversetter")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $model.speakAutomatically) {
                        Image(systemName: model.speakAutomatically ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .toggleStyle(.button)
                    .accessibilityLabel("Les opp automatisk")
                }
            }
        }
        .task {
            model.preload()
            model.handleListenRequest()
        }
        .onReceive(NotificationCenter.default.publisher(for: .listenRequested)) { _ in
            model.handleListenRequest()
        }
    }

    // MARK: - Deler av skjermen

    private var languageBar: some View {
        HStack {
            languagePicker(selection: $model.source)
            Button {
                withAnimation { model.swapLanguages() }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3.weight(.semibold))
                    .padding(10)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .accessibilityLabel("Bytt språk")
            languagePicker(selection: $model.target)
        }
    }

    private func languagePicker(selection: Binding<Language>) -> some View {
        Picker("Språk", selection: selection) {
            ForEach(Language.allCases) { language in
                Text(language.displayName).tag(language)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.source.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Skriv eller snakk …", text: $model.inputText, axis: .vertical)
                .lineLimit(3...8)
                .font(.title3)
                .focused($inputFocused)
                .multilineTextAlignment(model.source.isRightToLeft ? .trailing : .leading)
                .environment(\.layoutDirection, model.source.isRightToLeft ? .rightToLeft : .leftToRight)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                inputFocused = false
                model.toggleRecording()
            } label: {
                Label(model.isRecording ? "Stopp" : "Snakk",
                      systemImage: model.isRecording ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isRecording ? .red : .accentColor)
            .disabled(model.isBusy)

            Button {
                inputFocused = false
                model.translate()
            } label: {
                Label("Oversett", systemImage: "character.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy || model.isRecording || model.inputText.isEmpty)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .idle:
            if let duration = model.lastDuration {
                Text(String(format: "Oversatt på %.1f s, helt lokalt", duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .loading(let message), .working(let message):
            HStack(spacing: 8) {
                ProgressView()
                Text(message).font(.callout)
            }
        case .recording:
            Label("Lytter … trykk Stopp når du er ferdig", systemImage: "waveform")
                .font(.callout)
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.target.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.outputText.isEmpty {
                    Button { model.speak() } label: { Image(systemName: "speaker.wave.2") }
                        .accessibilityLabel("Les opp")
                    Button { UIPasteboard.general.string = model.outputText } label: { Image(systemName: "doc.on.doc") }
                        .accessibilityLabel("Kopier")
                }
            }
            Text(model.outputText.isEmpty ? "Oversettelsen kommer her" : model.outputText)
                .font(.title3)
                .foregroundStyle(model.outputText.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: model.target.isRightToLeft ? .trailing : .leading)
                .multilineTextAlignment(model.target.isRightToLeft ? .trailing : .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
