// Copyright 2026 Dayloft contributors. GPL-3.0-or-later. See LICENSE and NOTICE.md.
import SwiftUI

private enum DayloftStyle {
    static let background = Color(red: 0.045, green: 0.063, blue: 0.072)
    static let panel = Color.white.opacity(0.035)
    static let line = Color.white.opacity(0.12)
    static let muted = Color(red: 0.61, green: 0.66, blue: 0.67)
    static let blue = Color(red: 0.66, green: 0.86, blue: 0.72)
}

struct DayloftMark: View {
    var size: CGFloat = 100
    var body: some View {
        ZStack {
            Horizon().stroke(.white.opacity(0.94), style: StrokeStyle(lineWidth: size / 65, lineCap: .round))
            Circle().fill(.white.opacity(0.96)).frame(width: size * 0.12, height: size * 0.12).offset(y: -size * 0.07)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
    private struct Horizon: Shape {
        func path(in r: CGRect) -> Path {
            Path { p in
                for radius in [0.23, 0.36] {
                    p.addArc(center: CGPoint(x: r.midX, y: r.height * 0.55), radius: r.width * radius,
                             startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                }
                p.move(to: CGPoint(x: r.width * 0.08, y: r.height * 0.65))
                p.addLine(to: CGPoint(x: r.width * 0.92, y: r.height * 0.65))
                p.move(to: CGPoint(x: r.width * 0.28, y: r.height * 0.78))
                p.addLine(to: CGPoint(x: r.width * 0.72, y: r.height * 0.78))
            }
        }
    }
}

struct DayloftRootView: View {
    @ObservedObject var model: DayloftModel
    @ObservedObject private var updates = DayloftUpdater.shared
    @State private var editingSchedule: DayloftSchedule?
    @State private var showMode = false
    @State private var showStart = false
    @State private var showActive = false
    @State private var showStreak = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(DayloftStyle.line).frame(width: 1)
            Group {
                if model.tab == 0 { home } else { schedules }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DayloftStyle.background)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .tint(DayloftStyle.blue)
        .frame(minWidth: 820, minHeight: 690)
        .sheet(item: $editingSchedule) { schedule in
            ScheduleEditor(model: model, original: schedule)
        }
        .sheet(isPresented: $showMode) { ModeEditor(model: model) }
        .sheet(isPresented: $showStart) { StartSessionSheet(model: model) }
        .sheet(isPresented: $showActive) { ActiveSessionSheet(model: model) }
        .sheet(isPresented: $model.showSettings) { DayloftSettingsView() }
        .sheet(isPresented: $model.showHelp) { DayloftHelpView() }
        .alert("Dayloft couldn’t save that change", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "Please try again.") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                DayloftMark(size: 28)
                Text("dayloft").font(.system(size: 27, weight: .medium, design: .rounded)).tracking(-1)
            }.padding(.top, 43).padding(.bottom, 46)
            Text("A LITTLE ROOM FOR YOU").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(DayloftStyle.muted).padding(.leading, 12).padding(.bottom, 15)
            navigation("Home", symbol: "sun.horizon", tag: 0, key: "1")
            navigation("Schedules", symbol: "calendar", tag: 1, key: "2")
            Spacer()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dayloft").font(.system(size: 12, weight: .medium))
                    Text(updates.availableVersion.map { "Version \($0) available" } ?? "Version \(updates.version)")
                        .font(.system(size: 10)).foregroundStyle(DayloftStyle.muted)
                }
                Spacer(minLength: 0)
                Button { updates.checkForUpdates() } label: {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(updates.availableVersion == nil ? DayloftStyle.muted : .white)
                        .frame(width: 32, height: 32)
                        .background(updates.availableVersion == nil ? Color.white.opacity(0.06) : Color.blue, in: Circle())
                }.buttonStyle(.plain).disabled(!updates.canRequest).help(updates.buttonHelp)
                    .accessibilityLabel(updates.availableVersion == nil ? "Check for updates" : "Install available update")
                    .accessibilityIdentifier("dayloft.update")
            }.padding(.horizontal, 8).padding(.bottom, 27)
        }.padding(.horizontal, 20).frame(width: 195)
    }
    private func navigation(_ title: String, symbol: String, tag: Int, key: KeyEquivalent) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { model.tab = tag } } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .regular)).frame(width: 20)
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
            }.padding(.horizontal, 13).padding(.vertical, 13)
                .foregroundStyle(model.tab == tag ? DayloftStyle.blue : DayloftStyle.muted)
                .background(model.tab == tag ? DayloftStyle.blue.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).keyboardShortcut(key, modifiers: .command).padding(.bottom, 7)
            .accessibilityIdentifier("dayloft.tab.\(tag)")
    }
    private var home: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.running ? (model.paused ? "Take a breath." : "You’re right here.") : "Make room for today.").font(.system(size: 30, weight: .medium, design: .serif)).tracking(-0.6)
                        Text(model.running ? "One thing at a time is enough." : "Less noise. A little more of what matters.").font(.system(size: 13)).foregroundStyle(DayloftStyle.muted)
                    }
                    Spacer()
                    Button { showStreak.toggle() } label: {
                        HStack(spacing: 7) {
                            Image(systemName: model.activity.todayQualifies ? "flame.fill" : "flame")
                            Text(model.streak > 0 ? "\(model.streak) day streak" : "Start a streak")
                        }.font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DayloftStyle.blue).padding(.horizontal, 13).padding(.vertical, 10)
                            .background(DayloftStyle.blue.opacity(0.09), in: Capsule())
                            .overlay(Capsule().stroke(DayloftStyle.blue.opacity(0.22)))
                    }.buttonStyle(.plain).padding(.top, 3).accessibilityIdentifier("dayloft.streak")
                        .popover(isPresented: $showStreak) { streakDetails }
                }.padding(.bottom, 27)
                if !model.enforcementError.isEmpty {
                    Label(model.enforcementError, systemImage: "exclamationmark.shield")
                        .font(.system(size: 13)).foregroundStyle(.orange)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 16)
                }
                focusCard
                HStack(spacing: 6) {
                    Text("Mode:").foregroundStyle(DayloftStyle.muted)
                    if model.running { Text(model.activeMode) }
                    else {
                        Menu {
                            ForEach(model.modes, id: \.self) { mode in
                                Button(mode) { model.selectMode(mode) }
                            }
                            Divider()
                            Button("Edit this mode…") { showMode = true }
                        } label: {
                            HStack(spacing: 6) { Text(model.mode); Image(systemName: "chevron.down").font(.system(size: 10)) }
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(.white).disabled(model.busy)
                            .accessibilityLabel("Focus mode")
                    }
                }.font(.system(size: 13, weight: .medium)).padding(.top, 22)
                if !model.running {
                    Button {
                        showMode = true
                    } label: {
                        Text(model.domains.isEmpty && !model.allowlist ? "Choose your distractions  +" : "\(model.domains.count) websites to \(model.allowlist ? "allow" : "block")  ·  Edit")
                            .font(.system(size: 11)).foregroundStyle(DayloftStyle.muted)
                    }.buttonStyle(.plain).padding(.top, 10).disabled(model.busy).accessibilityIdentifier("dayloft.editMode")
                } else {
                    Text("\(model.activeDomains.count) websites \(model.activeAllowlist ? "allowed" : "blocked") · \(model.breaksRemaining) breaks left")
                        .font(.system(size: 11)).foregroundStyle(DayloftStyle.muted).padding(.top, 10)
                }
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TIME WELL SPENT").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(DayloftStyle.muted)
                        Text(DayloftModel.clock(model.focusToday)).font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text("Focused today · breaks excluded").font(.system(size: 10)).foregroundStyle(DayloftStyle.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(DayloftStyle.line).frame(width: 1, height: 62)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("YOUR LAST 7 DAYS").font(.system(size: 9, weight: .semibold)).tracking(1.2)
                            Spacer(minLength: 3)
                            Text("\(model.activity.focusedDays)/7").font(.system(size: 10)).monospacedDigit()
                        }.foregroundStyle(DayloftStyle.muted)
                        activityWeek
                    }.frame(maxWidth: .infinity)
                }.padding(.top, 28).padding(.bottom, 26)
                Button {
                    if model.running {
                        model.takeBreak()
                    } else if model.domains.isEmpty && !model.allowlist { showMode = true }
                    else { showStart = true }
                } label: {
                    HStack(spacing: 9) {
                        if model.busy { ProgressView().controlSize(.small) }
                        else { Image(systemName: model.running ? "cup.and.saucer" : "play.fill").font(.system(size: 12)) }
                        Text(model.busy ? "Starting your focus…" : model.paused ? "Enjoy your break" : model.running ? (model.breaksRemaining > 0 ? "Take a 5-minute break" : "Stay in your flow") : "Begin focus")
                            .font(.system(size: 16, weight: .medium))
                    }.frame(maxWidth: .infinity).padding(.vertical, 16)
                        .foregroundStyle(DayloftStyle.background)
                        .background(DayloftStyle.blue, in: RoundedRectangle(cornerRadius: 16))
                        .opacity(model.busy || model.acting || (model.running && (model.paused || model.breaksRemaining == 0)) ? 0.55 : 1)
                }.buttonStyle(.plain)
                    .disabled(model.busy || model.acting || (model.running && (model.paused || model.breaksRemaining == 0)))
                    .accessibilityIdentifier("dayloft.blockNow")
                Text(model.running ? "Your block ends automatically. Closing Dayloft keeps it going." : "Your time is yours. Make a little space for it.")
                    .font(.system(size: 10)).foregroundStyle(DayloftStyle.muted).padding(.top, 15)
                if model.running {
                    Button("Add websites or extend this session…") { showActive = true }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(DayloftStyle.muted).padding(.top, 12)
                }
            }.frame(maxWidth: 620).padding(.horizontal, 40).padding(.top, 44).padding(.bottom, 28).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
    }
    private var activityWeek: some View {
        HStack(spacing: 0) {
            ForEach(model.activity.days) { day in
                let today = Calendar.current.isDate(day.date, inSameDayAs: model.now)
                Button { showStreak = true } label: {
                    VStack(spacing: 7) {
                        ZStack {
                            Circle().fill(day.qualifies ? DayloftStyle.blue : Color.white.opacity(0.06))
                            if day.qualifies { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(DayloftStyle.background) }
                            else if today { Circle().fill(DayloftStyle.blue).frame(width: 4, height: 4) }
                        }.frame(width: 23, height: 23)
                            .overlay(Circle().stroke(today ? DayloftStyle.blue.opacity(0.75) : .clear).padding(-3))
                        Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9)).foregroundStyle(DayloftStyle.muted)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(DayloftModel.clock(day.seconds)) focused, \(day.qualifies ? "streak day earned" : "not yet earned")")
                    .help("\(day.date.formatted(date: .abbreviated, time: .omitted)) · \(DayloftModel.clock(day.seconds))")
            }
        }
    }
    private var streakDetails: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(model.streak > 0 ? "\(model.streak) days of showing up" : "Small steps count", systemImage: "flame.fill")
                .font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(DayloftStyle.blue)
            Text("Earn a day with at least one minute of recorded focus. Break time doesn’t count.").font(.system(size: 13))
            activityWeek
            Text(model.activity.todayQualifies ? "Today is earned. Come back tomorrow to keep it growing." : model.streak > 0 ? "Your streak is safe for now. Focus today to keep it going." : "Start a focus session to earn your first day.")
                .font(.system(size: 12)).foregroundStyle(DayloftStyle.muted)
            Text("Days follow your Mac’s current time zone. A missed day resets the streak.")
                .font(.system(size: 11)).foregroundStyle(DayloftStyle.muted)
        }.padding(24).frame(width: 340).background(DayloftStyle.background)
    }
    private var focusCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [Color(red: 0.12, green: 0.20, blue: 0.22), Color(red: 0.07, green: 0.11, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
            // Original code-drawn horizon, with a slow glow that respects Reduce Motion.
            TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 0.1, paused: reduceMotion)) { context in
                let pulse = reduceMotion ? 0.5 : (sin(context.date.timeIntervalSinceReferenceDate / 5) + 1) / 2
                ZStack {
                    Circle().fill(DayloftStyle.blue.opacity(0.05 + pulse * 0.025)).frame(width: 224, height: 224)
                    Circle().stroke(DayloftStyle.blue.opacity(0.10), lineWidth: 1).frame(width: 198, height: 198)
                    Circle().stroke(DayloftStyle.blue.opacity(0.07), lineWidth: 1).frame(width: 260, height: 260)
                }.offset(x: 178, y: 30)
            }.allowsHitTesting(false).accessibilityHidden(true)
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 7) {
                        Circle().fill(DayloftStyle.blue).frame(width: 5, height: 5)
                        Text(model.busy ? "GETTING READY" : !model.enforcementError.isEmpty ? "NEEDS ATTENTION" : model.paused ? "A MOMENT TO RESET" : model.running ? "FOCUS IS ON" : "YOUR FOCUS SPACE")
                            .font(.system(size: 9, weight: .semibold)).tracking(1.8)
                    }.foregroundStyle(DayloftStyle.blue)
                    if model.running {
                        Text(model.countdown).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                        Text(model.paused ? "Breathe. Your focus returns automatically." : "The distractions can wait.")
                            .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                    } else {
                        Text("A quieter Mac.\nA clearer mind.").font(.system(size: 32, weight: .regular, design: .serif)).lineSpacing(3)
                        Text("Give your attention somewhere to land.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer(minLength: 0)
                DayloftMark(size: 94).foregroundStyle(DayloftStyle.blue)
                    .shadow(color: DayloftStyle.blue.opacity(0.3), radius: 25)
            }.padding(32)
        }.frame(height: 231).clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(DayloftStyle.blue.opacity(0.16)))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dayloft.focusCard")
    }
    private var schedules: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Your rhythm.").font(.system(size: 32, weight: .medium, design: .serif)).tracking(-0.9)
                    Text("\(model.schedules.filter(\.enabled).count) routines enabled · set it, then let go.").font(.system(size: 13)).foregroundStyle(DayloftStyle.muted)
                }
                Spacer()
                Button {
                    var schedule = DayloftSchedule(); schedule.domains = model.domains; schedule.allowlist = model.allowlist; schedule.mode = model.mode
                    editingSchedule = schedule
                } label: {
                    Image(systemName: "plus").font(.system(size: 20, weight: .medium)).foregroundStyle(.black)
                        .frame(width: 39, height: 39).background(LinearGradient(colors: [DayloftStyle.blue, DayloftStyle.blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                }.buttonStyle(.plain).disabled(model.scheduleChangesLocked || model.saving).help("Create schedule").accessibilityLabel("Create schedule").keyboardShortcut("n", modifiers: .command)
            }.padding(.bottom, 28)
            if model.scheduleChangesLocked {
                HStack(spacing: 13) {
                    Image(systemName: "lock.fill").foregroundStyle(DayloftStyle.blue)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.running ? (model.paused ? "Your break is on" : "Focus is on") : "Starting your focus…")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Schedule changes unlock when this session ends.")
                            .font(.system(size: 11)).foregroundStyle(DayloftStyle.muted)
                    }
                    Spacer()
                    if model.running {
                        Text(model.countdown).font(.system(size: 17, weight: .medium)).monospacedDigit()
                    }
                }.padding(17).background(DayloftStyle.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                    .padding(.bottom, 16).accessibilityIdentifier("dayloft.scheduleSessionStatus")
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    if model.legacyPending {
                        HStack {
                            Image(systemName: "clock.badge.checkmark")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Previously scheduled block").font(.system(size: 13, weight: .medium))
                                Text(model.legacyDate.formatted()).font(.system(size: 11)).foregroundStyle(DayloftStyle.muted)
                            }
                            Spacer()
                            Button("Manage") { model.bridge.manageLegacySchedule() }.controlSize(.small).disabled(model.scheduleChangesLocked || model.saving)
                        }.padding(16).background(DayloftStyle.panel, in: RoundedRectangle(cornerRadius: 15))
                    }
                    ForEach(model.schedules) { schedule in
                        HStack(spacing: 16) {
                            Button { editingSchedule = schedule } label: {
                                HStack(spacing: 17) {
                                    Text(schedule.emoji).font(.system(size: 27)).frame(width: 49, height: 49).background(DayloftStyle.blue.opacity(schedule.enabled ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(schedule.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                                        Text("\(schedule.daysLabel)  ·  \(schedule.timeLabel)\(schedule.overnight ? " (+1 day)" : "")")
                                            .font(.system(size: 11)).foregroundStyle(DayloftStyle.muted)
                                            .lineLimit(1).minimumScaleFactor(0.8)
                                        Text("\(schedule.domains.count) websites · \(schedule.breaks == 0 ? "No breaks" : "\(schedule.breaks) five-minute \(schedule.breaks == 1 ? "break" : "breaks")")")
                                            .font(.system(size: 10)).foregroundStyle(DayloftStyle.muted.opacity(0.85))
                                    }
                                    Spacer(minLength: 0)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Edit \(schedule.name)").disabled(model.scheduleChangesLocked || model.saving)
                            Toggle(schedule.name, isOn: Binding(get: { schedule.enabled }, set: { enabled in
                                if enabled && schedule.domains.isEmpty && !schedule.allowlist {
                                    var draft = schedule; draft.enabled = true; editingSchedule = draft
                                } else { var draft = schedule; draft.enabled = enabled; model.save(draft) }
                            })).labelsHidden().toggleStyle(.switch).tint(DayloftStyle.blue)
                                .disabled(model.scheduleChangesLocked || model.saving).accessibilityLabel("Enable \(schedule.name)")
                        }.padding(.horizontal, 18).padding(.vertical, 14)
                            .background(DayloftStyle.panel, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(schedule.enabled ? DayloftStyle.blue.opacity(0.30) : DayloftStyle.line, lineWidth: 1))
                    }
                }.padding(.bottom, 15)
            }.scrollIndicators(.hidden)
            HStack(spacing: 7) {
                if model.saving { ProgressView().controlSize(.mini) } else { Image(systemName: "moon.stars").font(.system(size: 11)) }
                Text(model.saving ? "Saving your rhythm…" : "Enabled schedules run even when Dayloft is closed.")
                    .font(.system(size: 10))
            }.foregroundStyle(DayloftStyle.muted).padding(.top, 14)
            if !model.scheduleError.isEmpty { Text(model.scheduleError).font(.system(size: 11)).foregroundStyle(.orange).padding(.top, 7) }
        }.frame(maxWidth: 670).padding(.horizontal, 40).padding(.top, 44).padding(.bottom, 30).frame(maxWidth: .infinity)
    }
}

private struct StartSessionSheet: View {
    @ObservedObject var model: DayloftModel
    @Environment(\.dismiss) var dismiss
    @State private var duration = 45
    @State private var breaks = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack { DayloftMark(size: 32); Spacer(); Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(DayloftStyle.muted) }
            VStack(alignment: .leading, spacing: 8) {
                Text("A little space for you.").font(.system(size: 26, weight: .medium))
                Text("\(model.mode) · \(model.domains.count) websites to \(model.allowlist ? "allow" : "block")").foregroundStyle(DayloftStyle.muted)
            }
            VStack(alignment: .leading, spacing: 13) {
                Text("How long?").fontWeight(.medium)
                HStack(spacing: 9) {
                    ForEach([25, 45, 60, 90], id: \.self) { minutes in
                        Button("\(minutes)m") { duration = minutes }
                            .buttonStyle(.plain).frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(duration == minutes ? Color.white.opacity(0.15) : DayloftStyle.panel, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(DayloftStyle.line))
                    }
                }
                Stepper("\(duration) \(duration == 1 ? "minute" : "minutes")", value: $duration, in: 1...1440).font(.system(size: 12)).foregroundStyle(DayloftStyle.muted)
            }
            BreakPicker(breaks: $breaks)
            Text("Once you start, websites stay blocked until the timer ends—even if you quit or restart. Only your chosen breaks can pause it.")
                .font(.system(size: 12)).foregroundStyle(DayloftStyle.muted).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            Button { model.duration = duration; model.breaks = breaks; dismiss(); model.start() } label: {
                Label("Start my focus", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundStyle(.black).background(.white, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).keyboardShortcut(.defaultAction).disabled(model.running || model.busy)
        }.padding(32).frame(width: 410).background(DayloftStyle.background).preferredColorScheme(.dark)
            .onAppear { duration = model.duration; breaks = model.breaks }
    }
}

private struct BreakPicker: View {
    @Binding var breaks: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Room to breathe").fontWeight(.medium); Spacer(); Text("5 min each").font(.system(size: 11)).foregroundStyle(DayloftStyle.muted) }
            Picker("Breaks allowed", selection: $breaks) {
                Text("No breaks").tag(0)
                Text("1 break").tag(1)
                Text("2 breaks").tag(2)
                Text("3 breaks").tag(3)
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
}

private struct ModeEditor: View {
    @ObservedObject var model: DayloftModel
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var allowlist = false
    @State private var validation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Make \(model.mode) yours").font(.system(size: 25, weight: .medium))
                    Text("Choose the websites you want a little space from.").font(.system(size: 12)).foregroundStyle(DayloftStyle.muted)
                }
                Spacer()
            }
            DomainEditor(text: $text, allowlist: $allowlist)
            if !validation.isEmpty { Text(validation).font(.system(size: 12)).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save mode") {
                    let cleaned = model.bridge.cleanDomains(text)
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cleaned.isEmpty { validation = "Enter a website like reddit.com or paste its URL."; return }
                    model.domains = cleaned; model.allowlist = allowlist; model.persistConfiguration(); dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 460).background(DayloftStyle.background).preferredColorScheme(.dark)
            .onAppear { text = model.domains.joined(separator: "\n"); allowlist = model.allowlist }
    }
}

private struct DomainEditor: View {
    @Binding var text: String
    @Binding var allowlist: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Website behavior", selection: $allowlist) {
                Text("Block these websites").tag(false)
                Text("Only allow these websites").tag(true)
            }.labelsHidden().pickerStyle(.segmented)
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text("reddit.com\nyoutube.com\nOr paste a website link…").foregroundStyle(DayloftStyle.muted).padding(10).allowsHitTesting(false) }
                TextEditor(text: $text).font(.system(size: 13)).scrollContentBackground(.hidden).padding(5)
                    .accessibilityLabel("Websites, one per line").accessibilityIdentifier("dayloft.domains")
            }.frame(height: 145).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(DayloftStyle.line))
            Text(allowlist ? "All other internet destinations will be blocked. Local networks follow your existing preferences." : "One website or URL per line. Dayloft blocks the whole website across browsers, including links from search results.")
                .font(.system(size: 11)).foregroundStyle(DayloftStyle.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScheduleEditor: View {
    @ObservedObject var model: DayloftModel
    let original: DayloftSchedule
    @Environment(\.dismiss) var dismiss
    @State private var draft = DayloftSchedule()
    @State private var domains = ""
    @State private var validation = ""
    @State private var confirmDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(model.schedules.contains(where: { $0.id == original.id }) ? "Your rhythm" : "Make a little room").font(.system(size: 25, weight: .medium))
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(DayloftStyle.muted).keyboardShortcut(.cancelAction).disabled(model.saving)
            }
            HStack(spacing: 12) {
                Picker("Icon", selection: $draft.emoji) {
                    ForEach(["☕️", "🎯", "📚", "🎨", "🌙", "📵", "🌿", "✨"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 65)
                TextField("Schedule name", text: $draft.name).textFieldStyle(.roundedBorder).font(.system(size: 16)).accessibilityIdentifier("dayloft.scheduleName")
            }
            HStack {
                timePicker("From", minute: $draft.startMinute)
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(DayloftStyle.muted)
                Spacer()
                timePicker("Until", minute: $draft.endMinute)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(draft.daysLabel).font(.system(size: 12)).foregroundStyle(DayloftStyle.muted)
                    Spacer()
                    if draft.overnight { Text("Ends the next day").font(.system(size: 11)).foregroundStyle(DayloftStyle.muted) }
                }
                HStack(spacing: 8) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        Button {
                            if draft.days.contains(day) { draft.days.removeAll { $0 == day } } else { draft.days.append(day) }
                        } label: {
                            Text(Calendar.current.veryShortWeekdaySymbols[day - 1]).font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity).frame(height: 34)
                                .background(draft.days.contains(day) ? Color.white.opacity(0.17) : DayloftStyle.panel, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DayloftStyle.line))
                        }.buttonStyle(.plain).accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                            .accessibilityAddTraits(draft.days.contains(day) ? .isSelected : [])
                    }
                }
            }
            DomainEditor(text: $domains, allowlist: $draft.allowlist)
            BreakPicker(breaks: $draft.breaks)
            Toggle("Enable this schedule", isOn: $draft.enabled).toggleStyle(.switch).tint(DayloftStyle.blue)
            Text("Starts automatically, even with Dayloft closed. If you’re already focusing, this schedule waits and runs only until its end time. Schedule changes are locked while a focus session is running.")
                .font(.system(size: 11)).foregroundStyle(DayloftStyle.muted).fixedSize(horizontal: false, vertical: true)
            if !validation.isEmpty { Text(validation).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                if model.schedules.contains(where: { $0.id == original.id }) {
                    Button("Delete schedule", role: .destructive) { confirmDelete = true }.buttonStyle(.plain).foregroundStyle(DayloftStyle.muted)
                }
                Spacer()
                if model.saving { ProgressView().controlSize(.small) }
                Button("Save schedule") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.disabled(model.saving || model.scheduleChangesLocked)
            if model.scheduleChangesLocked { Text("Your session has started. You can change schedules after it ends.").font(.system(size: 11)).foregroundStyle(DayloftStyle.blue) }
        }.padding(30).frame(width: 470).background(DayloftStyle.background).preferredColorScheme(.dark)
            .interactiveDismissDisabled(model.saving)
            .onAppear { draft = original; domains = draft.domains.joined(separator: "\n") }
            .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete schedule", role: .destructive) { model.delete(original) { if $0 { dismiss() } } }
            } message: { Text("This removes future sessions. A block already running will finish normally.") }
    }
    private func timePicker(_ title: String, minute: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(DayloftStyle.muted)
            DatePicker(title, selection: Binding(get: {
                Calendar.current.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            }, set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minute.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }), displayedComponents: .hourAndMinute).labelsHidden()
        }
    }
    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.name.isEmpty else { validation = "Give your schedule a name."; return }
        guard !draft.days.isEmpty else { validation = "Choose at least one day."; return }
        guard draft.startMinute != draft.endMinute else { validation = "Choose a different end time."; return }
        draft.domains = model.bridge.cleanDomains(domains)
        if draft.enabled && draft.domains.isEmpty && !draft.allowlist { validation = "Add a website before enabling this schedule."; return }
        if !domains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.domains.isEmpty { validation = "Enter a valid website or URL."; return }
        model.save(draft) { if $0 { dismiss() } }
    }
}

private struct ActiveSessionSheet: View {
    @ObservedObject var model: DayloftModel
    @Environment(\.dismiss) var dismiss
    @State private var minutes = 15
    @State private var websites = ""
    @State private var pending = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Keep your flow").font(.system(size: 26, weight: .medium))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(pending)
            }
            Text("\(model.countdown) remaining").font(.system(size: 14)).foregroundStyle(DayloftStyle.muted).monospacedDigit()
            VStack(alignment: .leading, spacing: 12) {
                Text("A little more time").fontWeight(.medium)
                HStack {
                    Picker("Additional time", selection: $minutes) {
                        ForEach([5, 15, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                    }.labelsHidden()
                    Button("Extend session") {
                        pending = true
                        model.bridge.extendSession(minutes) { result in
                            pending = false
                            if let result { error = result.localizedDescription } else { model.refresh(); dismiss() }
                        }
                    }
                }
            }
            if !model.activeAllowlist {
                VStack(alignment: .leading, spacing: 10) {
                    Text("One more distraction?").fontWeight(.medium)
                    TextField("Paste a website or URL", text: $websites).textFieldStyle(.roundedBorder)
                    Button("Add to this block") {
                        guard !model.bridge.cleanDomains(websites).isEmpty else { error = "Enter a website like reddit.com."; return }
                        pending = true
                        model.bridge.addBlockedWebsites(websites) { result in
                            pending = false
                            if let result { error = result.localizedDescription } else { model.refresh(); dismiss() }
                        }
                    }
                }
            }
            Text("You can add distractions or give yourself more time. Your current block can’t be shortened.")
                .font(.system(size: 12)).foregroundStyle(DayloftStyle.muted)
            if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
            if pending { ProgressView().controlSize(.small) }
        }.padding(30).frame(width: 430).background(DayloftStyle.background).preferredColorScheme(.dark)
            .disabled(pending || !model.running).interactiveDismissDisabled(pending)
    }
}

private struct DayloftSettingsView: View {
    @ObservedObject private var updates = DayloftUpdater.shared
    @Environment(\.dismiss) var dismiss
    @AppStorage("BlockSoundShouldPlay") private var sound = false
    @AppStorage("AllowLocalNetworks") private var localNetwork = true
    @AppStorage("IncludeLinkedDomains") private var relatedWebsites = true
    @AppStorage("ClearCaches") private var clearCaches = true
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Text("The little details").font(.system(size: 25, weight: .medium)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Toggle("Play a sound when focus ends", isOn: $sound)
            DisclosureGroup("Website blocking") {
                VStack(alignment: .leading, spacing: 17) {
                    Toggle("Keep local devices reachable", isOn: $localNetwork)
                    Toggle("Include related website domains", isOn: $relatedWebsites)
                    Toggle("Clear browser caches when a block changes", isOn: $clearCaches)
                    Text("Cache clearing helps prevent saved pages from bypassing a block. These choices apply to future sessions and newly saved schedules.")
                        .font(.system(size: 11)).foregroundStyle(DayloftStyle.muted)
                }.padding(.top, 15)
            }
            Divider()
            Toggle("Automatically check for updates", isOn: Binding(get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) }))
                .disabled(!updates.configured)
            HStack {
                Text(updates.buttonHelp).font(.system(size: 11)).foregroundStyle(DayloftStyle.muted)
                Spacer()
                Button("Check now") { updates.checkForUpdates() }.disabled(!updates.canRequest)
            }
            Text("Your schedules and focus history stay on this Mac.\nNo account. No analytics. No subscription.")
                .font(.system(size: 12)).foregroundStyle(DayloftStyle.muted).lineSpacing(4)
        }.toggleStyle(.switch).tint(DayloftStyle.blue).padding(30).frame(width: 430)
            .background(DayloftStyle.background).preferredColorScheme(.dark)
    }
}

private struct DayloftHelpView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { DayloftMark(size: 34); Text("A little more room.").font(.system(size: 25, weight: .medium)); Spacer() }
            instruction("1", "Choose your distractions", "Pick a mode on Home and add websites. Full links work too—Dayloft blocks the whole website.")
            instruction("2", "Find your rhythm", "Block Now starts a session when you’re ready. Schedules repeat on the days you choose, even when the app is closed.")
            instruction("3", "Leave room to breathe", "Choose up to three five-minute breaks. When a break ends, your websites lock again automatically.")
            Text("A started block ends at its saved time. Quitting, restarting, or deleting Dayloft won’t shorten it. Disable schedules and let your current session finish before uninstalling.")
                .font(.system(size: 12)).foregroundStyle(DayloftStyle.muted).fixedSize(horizontal: false, vertical: true)
            Text("Native SwiftUI, powered by the open-source SelfControl engine. GPL-3.0-or-later. No warranty. Copyright notices and licenses are included with the source and release.")
                .font(.system(size: 10)).foregroundStyle(DayloftStyle.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open-source licenses") {
                    if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") { NSWorkspace.shared.open(url) }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(DayloftStyle.muted)
                Spacer(); Button("Got it") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(32).frame(width: 450).background(DayloftStyle.background).preferredColorScheme(.dark)
    }
    private func instruction(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Text(number).font(.system(size: 13, weight: .medium)).frame(width: 27, height: 27).background(.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(text).font(.system(size: 12)).foregroundStyle(DayloftStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
