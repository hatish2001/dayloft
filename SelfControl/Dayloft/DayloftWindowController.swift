// Copyright 2026 Dayloft contributors. GPL-3.0-or-later. See LICENSE and NOTICE.md.
import Cocoa
import SwiftUI
import Combine

@objc(DayloftWindowController)
final class DayloftWindowController: NSWindowController {
    private let model: DayloftModel
    private var updateObservation: AnyCancellable?
    @objc(initWithBridge:)
    init(bridge: SCDayloftBridge) {
        model = DayloftModel(bridge: bridge)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 810),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Dayloft"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedWhite: 0.03, alpha: 1)
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 840, height: 730)
        window.contentView = NSHostingView(rootView: DayloftRootView(model: model))
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DayloftMainWindow")
        super.init(window: window)
        updateObservation = model.$running.combineLatest(model.$busy, model.$saving, model.$acting).sink { running, starting, saving, acting in
            DayloftUpdater.shared.focusActive = running
            DayloftUpdater.shared.busy = starting || saving || acting
        }
        if !window.setFrameUsingName("DayloftMainWindow") { window.center() }
    }
    required init?(coder: NSCoder) { fatalError("Use init(bridge:)") }
    @objc func showPreferences() { model.showSettings = true }
    @objc func showHelp() { model.showHelp = true }
    @objc func refresh() { model.refresh() }
    override func showWindow(_ sender: Any?) { super.showWindow(sender); window?.makeKeyAndOrderFront(sender) }
}
