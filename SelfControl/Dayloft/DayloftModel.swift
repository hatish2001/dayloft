// Copyright 2026 Dayloft contributors. GPL-3.0-or-later. See LICENSE and NOTICE.md.
import Foundation
import Combine

final class DayloftModel: ObservableObject {
    let bridge: SCDayloftBridge
    @Published var tab = 0
    @Published var showSettings = false
    @Published var showHelp = false
    @Published var running = false
    @Published var paused = false
    @Published var busy = false
    @Published var saving = false
    @Published var acting = false
    @Published var error: String?
    @Published var enforcementError = ""
    @Published var now = Date()
    @Published var end = Date.distantPast
    @Published var breakEnd = Date.distantPast
    @Published var breaksRemaining = 0
    @Published var domains: [String] = []
    @Published var activeDomains: [String] = []
    @Published var activeAllowlist = false
    @Published var allowlist = false
    @Published var duration = 45
    @Published var breaks = 0
    @Published var mode = "Living"
    @Published var activeMode = "Focus"
    @Published var schedules: [DayloftSchedule] = []
    @Published var focusToday: TimeInterval = 0
    @Published var streak = 0
    @Published var activity = DayloftActivity(sessions: [], now: Date())
    @Published var legacyPending = false
    @Published var legacyDate = Date.distantPast
    @Published var scheduleError = ""
    private var timer: AnyCancellable?
    private let defaults = UserDefaults.standard
    let modes = ["Living", "Deep Work", "Offline"]

    init(bridge: SCDayloftBridge) {
        self.bridge = bridge
        let state = bridge.snapshot()
        domains = state["domains"] as? [String] ?? []
        allowlist = state["allowlist"] as? Bool ?? false
        duration = max(1, min(1440, state["duration"] as? Int ?? 45))
        breaks = state["breaks"] as? Int ?? 0
        mode = state["mode"] as? String ?? "Living"
        let remote = (state["schedules"] as? [[String: Any]] ?? []).compactMap(DayloftSchedule.init)
        let saved = (defaults.array(forKey: "DayloftDraftSchedules") as? [[String: Any]] ?? []).compactMap(DayloftSchedule.init)
        schedules = !remote.isEmpty ? remote : (!saved.isEmpty ? saved : DayloftSchedule.starters(domains: domains, allowlist: allowlist))
        refresh()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        let state = bridge.snapshot()
        now = Date(); running = state["running"] as? Bool ?? false
        paused = state["paused"] as? Bool ?? false; busy = state["busy"] as? Bool ?? false
        end = state["end"] as? Date ?? .distantPast; breakEnd = state["breakEnd"] as? Date ?? .distantPast
        breaksRemaining = state["breaksRemaining"] as? Int ?? 0
        activeDomains = state["activeDomains"] as? [String] ?? []
        activeAllowlist = state["activeAllowlist"] as? Bool ?? false
        legacyPending = state["legacyPending"] as? Bool ?? false
        legacyDate = state["legacyDate"] as? Date ?? .distantPast
        scheduleError = state["scheduleError"] as? String ?? ""
        enforcementError = state["enforcementError"] as? String ?? ""
        let history = state["sessions"] as? [[String: Any]] ?? []
        activeMode = history.last?["mode"] as? String ?? "Focus"
        let sessions = DayloftFocusSession.recorded(history, userID: getuid(), running: running,
            updated: state["updated"] as? Date ?? .distantPast, now: now)
        activity = DayloftActivity(sessions: sessions, now: now)
        focusToday = activity.today
        streak = activity.streak
    }
    var countdown: String { Self.clock(max(0, (paused ? breakEnd : end).timeIntervalSince(now))) }
    static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02dh %02dm %02ds", value / 3600, (value % 3600) / 60, value % 60)
    }
    func persistConfiguration() {
        guard !running && !busy else { return }
        bridge.configureDomains(domains, allowlist: allowlist, duration: duration, mode: mode)
        defaults.set(breaks, forKey: "BreaksPerBlock")
        defaults.set(["domains": domains, "allowlist": allowlist], forKey: "DayloftMode.\(mode)")
    }
    func selectMode(_ name: String) {
        persistConfiguration(); mode = name
        let config = defaults.dictionary(forKey: "DayloftMode.\(name)")
        domains = config?["domains"] as? [String] ?? []
        allowlist = config?["allowlist"] as? Bool ?? false
        persistConfiguration()
    }
    func takeBreak() {
        guard !acting else { return }; acting = true
        bridge.takeBreak { [weak self] error in
            self?.acting = false
            if let error { self?.error = error.localizedDescription }
            self?.refresh()
        }
    }
    func start() { persistConfiguration(); bridge.startBlock(); refresh() }
    func save(_ schedule: DayloftSchedule, completion: @escaping (Bool) -> Void = { _ in }) {
        var all = schedules
        if let i = all.firstIndex(where: { $0.id == schedule.id }) { all[i] = schedule } else { all.append(schedule) }
        commit(all, completion: completion)
    }
    func delete(_ schedule: DayloftSchedule, completion: @escaping (Bool) -> Void) {
        commit(schedules.filter { $0.id != schedule.id }, completion: completion)
    }
    private func commit(_ all: [DayloftSchedule], completion: @escaping (Bool) -> Void) {
        guard !saving else { return }; saving = true
        let values = all.map(\.dictionary)
        let hadRemote = !(bridge.snapshot()["schedules"] as? [[String: Any]] ?? []).isEmpty
        // Local inactive drafts need no administrator authorization.
        if !hadRemote && !all.contains(where: \.enabled) {
            schedules = all; defaults.set(values, forKey: "DayloftDraftSchedules"); saving = false; completion(true); return
        }
        bridge.saveSchedules(values) { [weak self] error in
            guard let self else { return }; self.saving = false
            if let error { self.error = error.localizedDescription; completion(false) }
            else { self.schedules = all; self.defaults.set(values, forKey: "DayloftDraftSchedules"); self.refresh(); completion(true) }
        }
    }
}
