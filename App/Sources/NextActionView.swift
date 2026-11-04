import SwiftUI

private let accent = Color(red: 0.98, green: 0.62, blue: 0.25)

/// "Not sure what to do next?" — pick an area, say how you usually get started,
/// pick one small first action, commit to a deadline. Then the normal countdown takes over.
struct NextActionView: View {
    @EnvironmentObject var store: Store
    @Binding var screen: Screen
    @StateObject private var transcriber = Transcriber()

    private enum Step { case area, describe, pick, commit }

    @State private var step: Step = .area
    @State private var area: FocusArea?
    @State private var suggestions: [Suggestion] = []
    @State private var loading = false
    @State private var error: String?
    @State private var action = ""
    @State private var lead = 5
    @FocusState private var actionFocused: Bool
    private let leads = [2, 5, 10, 15, 20, 30, 45]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button("Back") { back() }.foregroundStyle(.secondary)
            switch step {
            case .area: areaStep
            case .describe: describeStep
            case .pick: pickStep
            case .commit: commitStep
            }
        }
        .padding()
        .onDisappear { transcriber.stop() }
    }

    // MARK: steps

    private var areaStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Not sure what to do next?").font(.largeTitle.bold())
            Text("Pick one area. You'll commit to one small action, not the whole thing.")
                .foregroundStyle(.secondary)
            ForEach(FocusArea.allCases) { a in
                Button {
                    area = a
                    step = .describe
                } label: {
                    HStack {
                        Image(systemName: a.symbol).frame(width: 32)
                        Text(a.rawValue)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                }
                .foregroundStyle(.white)
            }
            Spacer()
        }
    }

    private var describeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How do you usually get started?").font(.title.bold())
            Text("Talk through what you normally do before \(area?.rawValue.lowercased() ?? "it") begins.")
                .foregroundStyle(.secondary)
            TextEditor(text: $transcriber.text)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 160)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
            HStack {
                Spacer()
                Button {
                    Task { await transcriber.toggle() }
                } label: {
                    Image(systemName: transcriber.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(transcriber.isRecording ? Color.red : accent))
                        .foregroundStyle(.black)
                }
                Spacer()
            }
            Text(transcriber.isRecording ? "Listening… tap to stop" : "Tap to speak, or type above")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            if let e = transcriber.error { Text(e).font(.callout).foregroundStyle(.red) }
            Spacer()
            BigButton(title: "Find my first action", enabled: !routine.isEmpty) {
                transcriber.stop()
                step = .pick
                Task { await fetch() }
            }
        }
    }

    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick one first action").font(.title.bold())
            if loading {
                Spacer()
                ProgressView().frame(maxWidth: .infinity)
                Spacer()
            } else if let error {
                Text(error).foregroundStyle(.red)
                Button("Try again") { Task { await fetch() } }.buttonStyle(.bordered)
                Spacer()
            } else {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .center, spacing: 14) {
                        Text(s.icon).font(.system(size: 38))
                        Text(s.action).font(.callout).lineLimit(3)
                        Spacer(minLength: 0)
                        VStack(spacing: 8) {
                            Button("Use this") { choose(s.action, edit: false) }
                                .buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
                            Button("Edit") { choose(s.action, edit: true) }
                                .buttonStyle(.bordered)
                        }
                        .font(.callout)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                }
                Spacer()
            }
            Button("None of these — write my own") { choose("", edit: true) }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var commitStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Commit to it").font(.title.bold())
            TextField("Your one small action", text: $action, axis: .vertical)
                .font(.title3)
                .focused($actionFocused)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
            Text("Do it within").font(.headline).padding(.top, 8)
            Picker("Minutes", selection: $lead) {
                ForEach(leads, id: \.self) { Text("\($0)m").tag($0) }
            }
            .pickerStyle(.segmented)
            Text("You can do it right away. This is just the latest you'll do it by.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            BigButton(title: "Start the clock", enabled: !trimmedAction.isEmpty) {
                if let m = store.begin(label: trimmedAction, kind: "action", leadMinutes: lead) {
                    Task { await Bells.schedule(for: m) }
                }
                screen = .countdown
            }
        }
    }

    // MARK: helpers

    private var routine: String { transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedAction: String { action.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func fetch() async {
        guard let area else { return }
        loading = true
        error = nil
        do {
            suggestions = try await NextActionClient().suggest(area: area.rawValue, routine: routine)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func choose(_ text: String, edit: Bool) {
        action = text
        step = .commit
        // give the text field a moment to appear before focusing it
        if edit { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { actionFocused = true } }
    }

    private func back() {
        transcriber.stop()
        switch step {
        case .area: screen = .home
        case .describe: step = .area
        case .pick: step = .describe
        case .commit: step = .pick
        }
    }
}
