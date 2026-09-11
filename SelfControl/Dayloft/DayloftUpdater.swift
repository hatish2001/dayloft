// Copyright 2026 Dayloft contributors. GPL-3.0-or-later.
import AppKit
import Combine
import Sparkle

final class DayloftUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, NSMenuItemValidation {
    static let shared = DayloftUpdater()
    @Published private(set) var configured = false
    @Published private(set) var canCheck = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var status = "Updates aren’t available in this development build."
    @Published var focusActive = false { didSet { resumeDeferredInstallation() } }
    @Published var busy = false { didSet { resumeDeferredInstallation() } }
    @Published private(set) var automaticChecks = false
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?
    private var deferredInstallation: (() -> Void)?
    var canRequest: Bool { DayloftUpdatePolicy.canRequestUpdate(configured: configured, canCheck: canCheck, focusActive: focusActive, busy: busy) }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    var buttonHelp: String { focusActive || busy ? "Updates are available when your focus session and changes finish." : status }

    private override init() {
        super.init()
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        configured = DayloftUpdatePolicy.isConfigured(feed: feed, publicKey: key)
        if configured {
            let value = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
            controller = value
            observation = value.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).sink { [weak self] in self?.canCheck = $0 }
            value.startUpdater()
            automaticChecks = value.updater.automaticallyChecksForUpdates
            status = "Check for updates"
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let menu = NSApp.mainMenu?.items.first?.submenu else { return }
            let item = NSMenuItem(title: "Check for Updates…", action: #selector(self.checkForUpdates), keyEquivalent: "")
            item.target = self; menu.insertItem(item, at: min(2, menu.items.count))
        }
    }
    @objc func checkForUpdates() {
        guard canRequest else { return }
        status = "Checking for updates…"
        controller?.checkForUpdates(nil)
    }
    func setAutomaticChecks(_ enabled: Bool) {
        guard let controller else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
        automaticChecks = controller.updater.automaticallyChecksForUpdates
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canRequest }
    // Discovery is quiet; the blue sidebar button opens Sparkle's signed
    // download/install UI. Installation remains an explicit user action.
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
        status = "Dayloft \(update.displayVersionString) is available"
    }
    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        status = "Check for updates"
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if focusActive || busy { throw NSError(domain: "DayloftUpdates", code: 1, userInfo: [NSLocalizedDescriptionKey: "Finish your focus session before updating Dayloft."]) }
    }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        try self.updater(updater, mayPerform: updateCheck)
    }
    // A schedule can start while an update downloads. Keep the helper and
    // front end together until that session and pending changes have finished.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard focusActive || busy else { return false }
        deferredInstallation = installHandler
        status = "Update ready. Installation will continue after your focus session."
        return true
    }
    private func resumeDeferredInstallation() {
        guard !focusActive, !busy, let install = deferredInstallation else { return }
        deferredInstallation = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.focusActive || self.busy { self.deferredInstallation = install }
            else { install() }
        }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        status = "Dayloft \(item.displayVersionString) is available"
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { availableVersion = nil; status = "You’re up to date." }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { status = error.localizedDescription }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
}
