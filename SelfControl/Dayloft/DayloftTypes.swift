// Copyright 2026 Dayloft contributors. GPL-3.0-or-later. See LICENSE and NOTICE.md.
// Dayloft for macOS. GPL-3.0-or-later.
import Foundation

struct DayloftSchedule: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name = "Deep Work"
    var emoji = "🎯"
    var mode = "Living"
    var startMinute = 660
    var endMinute = 900
    var days = [2, 3, 4, 5, 6]
    var enabled = false
    var breaks = 1
    var domains: [String] = []
    var allowlist = false

    var dictionary: [String: Any] {
        ["id": id, "name": name, "emoji": emoji, "mode": mode, "startMinute": startMinute,
         "endMinute": endMinute, "days": days, "enabled": enabled, "breaks": breaks,
         "domains": domains, "allowlist": allowlist]
    }
    init() {}
    init?(_ d: [String: Any]) {
        guard let id = d["id"] as? String, let name = d["name"] as? String,
              let start = d["startMinute"] as? Int, let end = d["endMinute"] as? Int,
              let days = d["days"] as? [Int] else { return nil }
        self.id = id; self.name = name; startMinute = start; endMinute = end; self.days = days
        emoji = d["emoji"] as? String ?? "✦"; mode = d["mode"] as? String ?? "Living"
        enabled = d["enabled"] as? Bool ?? false; breaks = d["breaks"] as? Int ?? 0
        domains = d["domains"] as? [String] ?? []; allowlist = d["allowlist"] as? Bool ?? false
    }
    var daysLabel: String {
        let set = Set(days)
        if set == Set(1...7) { return "Every Day" }
        if set == Set(2...6) { return "Weekdays" }
        if set == Set([1, 7]) { return "Weekends" }
        return [2, 3, 4, 5, 6, 7, 1].filter { set.contains($0) }.map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }
    static func time(_ minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
    var timeLabel: String { "\(Self.time(startMinute)) – \(Self.time(endMinute))" }
    var overnight: Bool { endMinute < startMinute }
    static func starters(domains: [String], allowlist: Bool) -> [Self] {
        let values: [(String, String, Int, Int, [Int])] = [
            ("Morning Zen", "☕️", 360, 540, Array(1...7)),
            ("Deep Work", "🎯", 660, 900, Array(2...6)),
            ("Focus Zone", "📚", 960, 1080, Array(1...7)),
            ("Making it", "🎨", 1200, 1320, Array(2...6)),
            ("Night Guard", "🌙", 1380, 0, Array(1...7)),
            ("Full Focus", "📵", 0, 1439, Array(1...7))]
        return values.enumerated().map { index, value in
            var s = Self(); s.id = "dayloft-starter-\(index)"; s.name = value.0; s.emoji = value.1
            s.startMinute = value.2; s.endMinute = value.3; s.days = value.4
            s.domains = domains; s.allowlist = allowlist; return s
        }
    }
    static func applyingMode(_ mode: String, domains: [String], allowlist: Bool, to schedules: [Self]) -> [Self] {
        schedules.map { schedule in
            guard schedule.mode == mode else { return schedule }
            var updated = schedule
            updated.domains = domains
            updated.allowlist = allowlist
            if updated.enabled && domains.isEmpty && !allowlist { updated.enabled = false }
            return updated
        }
    }
    static func resolvingModeConfigurations(_ configurations: [String: Any], in schedules: [Self]) -> [Self] {
        configurations.reduce(schedules) { result, item in
            guard let value = item.value as? [String: Any],
                  let domains = value["domains"] as? [String],
                  let allowlist = value["allowlist"] as? Bool else { return result }
            return applyingMode(item.key, domains: domains, allowlist: allowlist, to: result)
        }
    }
}

struct DayloftFocusSession {
    let start: Date
    let end: Date
    let breaks: [DateInterval]
    // Union the actual focus intervals. Duplicate history cannot create extra
    // time, and overlapping break intervals are subtracted only once.
    static func seconds(in range: DateInterval, sessions: [Self], now: Date) -> TimeInterval {
        var focused: [DateInterval] = []
        for session in sessions {
            let lower = max(range.start, session.start), upper = min(range.end, session.end, now)
            guard upper > lower else { continue }
            var cursor = lower
            for pause in session.breaks.sorted(by: { $0.start < $1.start }) {
                let start = max(lower, pause.start), end = min(upper, pause.end)
                guard end > start else { continue }
                if start > cursor { focused.append(DateInterval(start: cursor, end: start)) }
                cursor = max(cursor, end)
            }
            if cursor < upper { focused.append(DateInterval(start: cursor, end: upper)) }
        }
        let sorted = focused.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var total: TimeInterval = 0
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                total += current.duration; current = interval
            }
        }
        return total + current.duration
    }
    static let qualifyingSeconds: TimeInterval = 60

    static func recorded(_ history: [[String: Any]], userID: UInt32, running: Bool, updated: Date, now: Date) -> [Self] {
        history.compactMap { item in
            guard let owner = item["uid"] as? NSNumber, owner.uint32Value == userID,
                  let start = item["start"] as? Date, let end = item["end"] as? Date,
                  end > start, start <= now else { return nil }
            let breaks = (item["breaks"] as? [[String: Any]] ?? []).compactMap { value -> DateInterval? in
                guard let start = value["start"] as? Date, let end = value["end"] as? Date, end > start else { return nil }
                return DateInterval(start: start, end: end)
            }
            let recordedEnd = !running && end > now ? min(end, updated) : end
            guard recordedEnd > start else { return nil }
            return Self(start: start, end: recordedEnd, breaks: breaks)
        }
    }

    static func streak(sessions: [Self], now: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: now), count = 0
        for offset in 0..<3660 {
            let end = calendar.date(byAdding: .day, value: 1, to: day)!
            let seconds = seconds(in: DateInterval(start: day, end: end), sessions: sessions, now: now)
            if seconds >= qualifyingSeconds { count += 1 } else if offset > 0 { break }
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}


struct DayloftActivityDay: Identifiable {
    let date: Date
    let seconds: TimeInterval
    var id: Date { date }
    var qualifies: Bool { seconds >= DayloftFocusSession.qualifyingSeconds }
}

struct DayloftActivity {
    let days: [DayloftActivityDay]
    let streak: Int
    var today: TimeInterval { days.last?.seconds ?? 0 }
    var todayQualifies: Bool { days.last?.qualifies ?? false }
    var focusedDays: Int { days.filter(\.qualifies).count }

    init(sessions: [DayloftFocusSession], now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        days = (-6...0).compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return DayloftActivityDay(date: start, seconds: DayloftFocusSession.seconds(in: DateInterval(start: start, end: end), sessions: sessions, now: now))
        }
        streak = DayloftFocusSession.streak(sessions: sessions, now: now, calendar: calendar)
    }
}
