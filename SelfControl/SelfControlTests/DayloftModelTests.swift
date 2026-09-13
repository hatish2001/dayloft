import XCTest
final class DayloftModelTests: XCTestCase {
    func testFocusTotalsClipAtMidnightNowAndBreaks() {
        let midnight = Date(timeIntervalSince1970: 100_000)
        let session = DayloftFocusSession(start: midnight.addingTimeInterval(-3600), end: midnight.addingTimeInterval(7200), breaks: [DateInterval(start: midnight.addingTimeInterval(300), duration: 300)])
        let range = DateInterval(start: midnight, duration: 86400)
        XCTAssertEqual(DayloftFocusSession.seconds(in: range, sessions: [session], now: midnight.addingTimeInterval(450)), 300)
        XCTAssertEqual(DayloftFocusSession.seconds(in: range, sessions: [session], now: midnight.addingTimeInterval(3600)), 3300)
        XCTAssertEqual(DayloftFocusSession.seconds(in: range, sessions: [session], now: midnight.addingTimeInterval(9000)), 6900)
    }
    func testFutureSessionsDoNotCountAndBreaksOutsideWindowAreIgnored() {
        let now = Date()
        let future = DayloftFocusSession(start: now.addingTimeInterval(100), end: now.addingTimeInterval(200), breaks: [])
        let past = DayloftFocusSession(start: now.addingTimeInterval(-600), end: now, breaks: [DateInterval(start: now.addingTimeInterval(-1000), duration: 100)])
        let range = DateInterval(start: now.addingTimeInterval(-600), duration: 1200)
        XCTAssertEqual(DayloftFocusSession.seconds(in: range, sessions: [future, past], now: now), 600)
    }
    func testStreakCanContinueFromYesterdayButStopsAtGap() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_789_088_400)
        let today = calendar.startOfDay(for: now)
        func session(_ days: Int) -> DayloftFocusSession {
            let start = calendar.date(byAdding: .day, value: -days, to: today)!
            return DayloftFocusSession(start: start, end: start.addingTimeInterval(300), breaks: [])
        }
        XCTAssertEqual(DayloftFocusSession.streak(sessions: [session(1), session(2), session(4)], now: now, calendar: calendar), 2)
        XCTAssertEqual(DayloftFocusSession.streak(sessions: [], now: now, calendar: calendar), 0)
    }
    func testScheduleRoundTripPreservesConfiguration() {
        var s = DayloftSchedule(); s.enabled = true; s.startMinute = 1380; s.endMinute = 0; s.domains = ["reddit.com"]
        XCTAssertEqual(DayloftSchedule(s.dictionary), s)
        XCTAssertTrue(s.overnight)
        XCTAssertEqual(s.daysLabel, "Weekdays")
    }
    func testStarterSchedulesAreNeverEnabledAutomatically() {
        let schedules = DayloftSchedule.starters(domains: ["example.com"], allowlist: false)
        XCTAssertEqual(schedules.count, 6)
        XCTAssertTrue(schedules.allSatisfy { !$0.enabled && $0.domains == ["example.com"] })
        XCTAssertEqual(Set(schedules.map(\.id)).count, schedules.count)
    }
    func testApplyingModeReplacesOnlySchedulesUsingThatMode() {
        var living = DayloftSchedule(); living.mode = "Living"; living.domains = ["old.example"]
        var offline = DayloftSchedule(); offline.mode = "Offline"; offline.domains = ["keep.example"]
        let updated = DayloftSchedule.applyingMode("Living", domains: ["x.com", "tiktok.com"], allowlist: false, to: [living, offline])
        XCTAssertEqual(updated[0].domains, ["x.com", "tiktok.com"])
        XCTAssertEqual(updated[1], offline)
    }
    func testClearingDenylistModeDisablesItsEnabledSchedules() {
        var living = DayloftSchedule(); living.mode = "Living"; living.enabled = true; living.domains = ["old.example"]
        let updated = DayloftSchedule.applyingMode("Living", domains: [], allowlist: false, to: [living])
        XCTAssertFalse(updated[0].enabled)
        XCTAssertTrue(updated[0].domains.isEmpty)
    }
    func testAuthoritativeModeConfigurationRepairsStaleScheduleCopy() {
        var living = DayloftSchedule(); living.mode = "Living"; living.domains = ["old.example"]
        let resolved = DayloftSchedule.resolvingModeConfigurations([
            "Living": ["domains": ["x.com", "tiktok.com"], "allowlist": false]
        ], in: [living])
        XCTAssertEqual(resolved[0].domains, ["x.com", "tiktok.com"])
    }
    func testOverlappingBreaksAreOnlySubtractedOnce() {
        let start = Date(timeIntervalSince1970: 100_000)
        let s = DayloftFocusSession(start: start, end: start.addingTimeInterval(600), breaks: [
            DateInterval(start: start.addingTimeInterval(100), duration: 200),
            DateInterval(start: start.addingTimeInterval(200), duration: 200)])
        XCTAssertEqual(DayloftFocusSession.seconds(in: DateInterval(start: start, duration: 600), sessions: [s], now: s.end), 300)
    }
    func testDuplicateAndOverlappingSessionsCannotInflateTime() {
        let start = Date(timeIntervalSince1970: 100_000)
        let a = DayloftFocusSession(start: start, end: start.addingTimeInterval(300), breaks: [])
        let b = DayloftFocusSession(start: start.addingTimeInterval(200), end: start.addingTimeInterval(500), breaks: [])
        XCTAssertEqual(DayloftFocusSession.seconds(in: DateInterval(start: start, duration: 600), sessions: [a, a, b], now: b.end), 500)
    }
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar
    }
    func testStreakThresholdAndWeekViewAgree() {
        let start = utc.startOfDay(for: Date(timeIntervalSince1970: 1_789_088_400))
        let s = DayloftFocusSession(start: start, end: start.addingTimeInterval(600), breaks: [])
        let before = DayloftActivity(sessions: [s], now: start.addingTimeInterval(59), calendar: utc)
        let earned = DayloftActivity(sessions: [s], now: start.addingTimeInterval(60), calendar: utc)
        XCTAssertEqual(before.streak, 0); XCTAssertFalse(before.todayQualifies)
        XCTAssertEqual(earned.streak, 1); XCTAssertTrue(earned.todayQualifies)
        XCTAssertEqual(earned.focusedDays, 1); XCTAssertEqual(earned.days.count, 7)
    }
    func testYesterdayGraceExpiresAfterMissedDay() {
        let day = utc.startOfDay(for: Date(timeIntervalSince1970: 1_789_088_400))
        let s = DayloftFocusSession(start: day, end: day.addingTimeInterval(120), breaks: [])
        let tomorrow = utc.date(byAdding: .day, value: 1, to: day)!
        let later = utc.date(byAdding: .day, value: 2, to: day)!
        XCTAssertEqual(DayloftActivity(sessions: [s], now: tomorrow, calendar: utc).streak, 1)
        XCTAssertEqual(DayloftActivity(sessions: [s], now: later, calendar: utc).streak, 0)
    }
    func testMidnightSessionDoesNotEarnTwoDaysFromOneMinute() {
        let midnight = utc.startOfDay(for: Date(timeIntervalSince1970: 1_789_088_400))
        let s = DayloftFocusSession(start: midnight.addingTimeInterval(-30), end: midnight.addingTimeInterval(30), breaks: [])
        let activity = DayloftActivity(sessions: [s], now: s.end, calendar: utc)
        XCTAssertEqual(activity.today, 30); XCTAssertEqual(activity.streak, 0); XCTAssertEqual(activity.focusedDays, 0)
    }
    func testBreakDoesNotAdvanceTodayOrStreak() {
        let start = utc.startOfDay(for: Date(timeIntervalSince1970: 1_789_088_400))
        let s = DayloftFocusSession(start: start, end: start.addingTimeInterval(600), breaks: [DateInterval(start: start.addingTimeInterval(40), duration: 300)])
        let activity = DayloftActivity(sessions: [s], now: start.addingTimeInterval(200), calendar: utc)
        XCTAssertEqual(activity.today, 40); XCTAssertEqual(activity.streak, 0)
    }
    func testDSTWeekUsesLocalDaysInsteadOf24HourOffsets() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = ISO8601DateFormatter().date(from: "2026-03-09T12:00:00-07:00")!
        let activity = DayloftActivity(sessions: [], now: now, calendar: calendar)
        XCTAssertEqual(activity.days.map { calendar.component(.day, from: $0.date) }, [3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(activity.days[6].date.timeIntervalSince(activity.days[5].date), 23 * 3600)
    }
    func testHistoryRequiresCurrentUserAndValidDates() {
        let now = Date(timeIntervalSince1970: 100_000)
        let row: [String: Any] = ["uid": NSNumber(value: 501), "start": now.addingTimeInterval(-100), "end": now]
        var wrong = row; wrong["uid"] = NSNumber(value: 502)
        var missing = row; missing.removeValue(forKey: "uid")
        var future = row; future["start"] = now.addingTimeInterval(100); future["end"] = now.addingTimeInterval(200)
        let values = DayloftFocusSession.recorded([row, wrong, missing, future], userID: 501, running: false, updated: now, now: now)
        XCTAssertEqual(values.count, 1)
    }
    func testStoppedHistoryCannotKeepAccruingWhileIdle() {
        let now = Date(timeIntervalSince1970: 100_000)
        let row: [String: Any] = ["uid": NSNumber(value: 501), "start": now.addingTimeInterval(-100), "end": now.addingTimeInterval(500)]
        let values = DayloftFocusSession.recorded([row], userID: 501, running: false, updated: now.addingTimeInterval(-40), now: now)
        XCTAssertEqual(values.first?.end, now.addingTimeInterval(-40))
        XCTAssertEqual(DayloftFocusSession.seconds(in: DateInterval(start: now.addingTimeInterval(-100), duration: 600), sessions: values, now: now), 60)
    }

}
