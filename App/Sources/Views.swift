import SwiftUI

private let accent = Color(red: 0.98, green: 0.62, blue: 0.25)

// MARK: - Home: streak + 12 months

struct HomeView: View {
    @EnvironmentObject var store: Store
    @Binding var screen: Screen

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button { screen = .settings } label: {
                    Image(systemName: "gearshape").font(.title3).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text("\(store.streak)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                Text(store.streak == 1 ? "morning won" : "mornings won in a row")
                    .foregroundStyle(.secondary)
            }
            MonthsGrid(months: store.months)
            Spacer(minLength: 0)
            if let today = store.today, !today.isRunning {
                Text(today.result == "won" ? "Today is won. See you tomorrow." : "Today is done. Tomorrow is a new start.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                BigButton(title: "Let's do it!") { screen = .setup }
            }
            StatusFooter()
        }
        .padding()
    }
}

struct MonthsGrid: View {
    let months: [(label: String, fill: Double?)]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 16) {
            ForEach(Array(months.enumerated()), id: \.offset) { _, month in
                VStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 7)
                        if let fill = month.fill {
                            Circle()
                                .trim(from: 0, to: max(fill, 0.001))
                                .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .frame(width: 52, height: 52)
                    Text(month.label)
                        .font(.caption)
                        .foregroundStyle(month.fill == nil ? Color.white.opacity(0.3) : Color.white)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct StatusFooter: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 2) {
            if let expiry = SigningInfo.expiry {
                let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                Text("Signed until \(expiry.formatted(.dateTime.weekday().day().month().hour().minute()))")
                    .foregroundStyle(daysLeft <= 1 ? .red : .secondary)
            } else {
                Text("Signed until: unknown")
            }
            if let error = store.backupError {
                Text("Backup: \(error)").foregroundStyle(.red)
            } else if let last = store.lastBackup {
                Text("Backed up: \(last.formatted(.relative(presentation: .named)))")
            } else {
                Text("Not backed up yet")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Setup: activity + lead time

struct SetupView: View {
    @EnvironmentObject var store: Store
    @Binding var screen: Screen
    @State private var activity: Activity?
    @State private var lead = 10
    private let leads = [5, 10, 15, 20, 30, 45]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button("Back") { screen = .home }.foregroundStyle(.secondary)
            Text("What's next?").font(.largeTitle.bold())
            ForEach(Activity.allCases) { a in
                Button { activity = a } label: {
                    HStack {
                        Image(systemName: a.symbol).frame(width: 32)
                        Text(a.rawValue)
                        Spacer()
                        if activity == a { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(activity == a ? 0.16 : 0.07)))
                }
                .foregroundStyle(.white)
            }
            Text("Start within").font(.headline).padding(.top, 8)
            Picker("Minutes", selection: $lead) {
                ForEach(leads, id: \.self) { Text("\($0)m").tag($0) }
            }
            .pickerStyle(.segmented)
            Spacer()
            BigButton(title: "Start the clock", enabled: activity != nil) {
                guard let activity else { return }
                store.start(activity: activity, leadMinutes: lead)
                if let m = store.current { Task { await Bells.schedule(for: m) } }
                screen = .countdown
            }
        }
        .padding()
    }
}

// MARK: - Countdown

struct CountdownView: View {
    @EnvironmentObject var store: Store
    @Binding var screen: Screen

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let m = store.current {
                content(m, now: context.date)
                    .onChange(of: context.date) { _, now in
                        if now >= m.failTime && store.evaluate(now: now) {
                            Task { await Bells.cancelAll() }
                            screen = .lost
                        }
                    }
            } else {
                Color.clear.onAppear { screen = .home }
            }
        }
    }

    private func content(_ m: Morning, now: Date) -> some View {
        let overdue = now >= m.deadline
        let remaining = max(0, (overdue ? m.failTime : m.deadline).timeIntervalSince(now))
        let total = m.deadline.timeIntervalSince(m.startedAt)
        let progress = overdue ? 1 : 1 - remaining / total
        return VStack(spacing: 28) {
            Spacer()
            Text(m.activity).font(.title2.bold()).multilineTextAlignment(.center)
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(overdue ? .red : accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 6) {
                    Text(clock(remaining))
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(overdue ? "until the challenge is lost" : "start by \(m.deadline.formatted(date: .omitted, time: .shortened))")
                        .font(.callout)
                        .foregroundStyle(overdue ? .red : .secondary)
                }
            }
            .frame(width: 280, height: 280)
            Spacer()
            BigButton(title: "I've started") {
                store.confirmStarted()
                Task { await Bells.cancelAll() }
                screen = .won
            }
            Text("Silencing the alarm is not starting.").font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    private func clock(_ s: TimeInterval) -> String {
        let t = Int(s.rounded(.up))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Outcomes

struct WonView: View {
    @EnvironmentObject var store: Store
    @Binding var screen: Screen

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "sunrise.fill").font(.system(size: 72)).foregroundStyle(accent)
            Text("Good job, one more day you have reduced rumination.\n\nKeep going. Step by Step.\n\nI believe in you.")
                .font(.title3)
                .multilineTextAlignment(.center)
            Text("Streak: \(store.streak)").font(.headline).foregroundStyle(accent)
            Spacer()
            BigButton(title: "Done") { screen = .home }
        }
        .padding()
    }
}

struct LostView: View {
    @Binding var screen: Screen

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "xmark.circle").font(.system(size: 72)).foregroundStyle(.red)
            Text("Challenge lost.").font(.largeTitle.bold())
            Text("As agreed: pay ₹500 to PM CARES today, on your honour.\n\nThe streak starts again tomorrow. One morning doesn't define the practice.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            BigButton(title: "Understood") { screen = .home }
        }
        .padding()
    }
}

struct PayCheckView: View {
    @EnvironmentObject var store: Store
    @Binding var screen: Screen
    @State private var notYet = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if notYet {
                Image(systemName: "indianrupeesign.circle").font(.system(size: 64)).foregroundStyle(.red)
                Text("Pay ₹500 to PM CARES today.").font(.title2.bold()).multilineTextAlignment(.center)
                Text("Why: you chose this cost yourself, so that mornings matter. A penalty that is quietly skipped teaches the mind that promises to yourself are optional — and rumination wins. Paying keeps your word worth something.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
                BigButton(title: "Close app") { exit(0) }
            } else {
                Text("Did you pay?").font(.largeTitle.bold())
                if let m = store.unpaid {
                    Text("You lost the challenge on \(m.date). The agreement was ₹500 to PM CARES.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                BigButton(title: "Yes, with honour") {
                    store.setPaid("yes")
                    screen = .home
                }
                Button("No, not yet") {
                    store.setPaid("not_yet")
                    notYet = true
                }
                .padding(.top, 4)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Binding var screen: Screen
    @State private var token = ""
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button("Back") { screen = .home }.foregroundStyle(.secondary)
            Text("Settings").font(.largeTitle.bold())

            Text("Backup token").font(.headline)
            SecureField(Keychain.token == nil ? "Paste token" : "Token saved — paste to replace", text: $token)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("Save token") {
                    Keychain.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    token = ""
                    status = "Saved"
                }
                Spacer()
                Button("Test & back up now") {
                    Task {
                        status = await BackupClient().ping()
                        await store.sync()
                    }
                }
            }
            .buttonStyle(.bordered)

            Text("Day-one test").font(.headline).padding(.top)
            Text("Turn on Sleep Focus, tap below, lock the phone. It must ring in about a minute.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Ring a test alarm in 1 minute") {
                Task { status = await Bells.testAlarm() }
            }
            .buttonStyle(.bordered)

            if !status.isEmpty { Text(status).foregroundStyle(accent) }
            Spacer()
            StatusFooter()
                .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

// MARK: - Shared

struct BigButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 18).fill(enabled ? accent : Color.gray.opacity(0.3)))
                .foregroundStyle(.black)
        }
        .disabled(!enabled)
    }
}
