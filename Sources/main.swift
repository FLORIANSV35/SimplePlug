import AVFoundation
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let engine = HostEngine()
    private let updater = Updater()
    private let defaults = UserDefaults.standard

    private var window: NSWindow!
    private let devicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let bufferPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let ratePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let pluginPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let latencyLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let loadGauge = NSLevelIndicator()
    private let loadLabel = NSTextField(labelWithString: "")
    private var meterTimer: Timer?
    private var shownLoad = 0.0, peakHold = 0.0, peakHoldSince = 0.0
    private let pluginContainer = NSView()
    private var containerWidth: NSLayoutConstraint!
    private var containerHeight: NSLayoutConstraint!
    private var content: NSStackView!

    private var interfaces: [AudioInterface] = []
    private var components: [AVAudioUnitComponent] = []
    private var pluginKey: String?
    private var micDenied = false

    private enum Key {
        static let device = "deviceUID", buffer = "bufferFrames", rate = "sampleRate", plugin = "pluginKey"
        static func state(_ plugin: String) -> String { "pluginState." + plugin }
    }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        refreshInterfaces()
        refreshPlugins()
        HAL.observeDeviceList { [weak self] in self?.devicesChanged() }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMeter() }
        }

        Task {
            micDenied = !(await AVCaptureDevice.requestAccess(for: .audio))
            restartAudio()
            let saved = defaults.string(forKey: Key.plugin)
            if let comp = components.first(where: { Self.key($0) == saved }) {
                pluginPopup.selectItem(withTitle: Self.title(comp))
                await loadPlugin(comp)
            }
            await updater.checkAtLaunch { [weak self] in self?.setStatus($0, error: false) }
        }
    }

    @objc private func checkForUpdates() {
        Task { await updater.check(interactive: true) { [weak self] in self?.setStatus($0, error: false) } }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        savePluginState()
        engine.stop()
    }

    // MARK: Window

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About SimplePlug", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let update = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit SimplePlug", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    private func buildWindow() {
        for popup in [devicePopup, bufferPopup, ratePopup, pluginPopup] {
            popup.target = self
        }
        devicePopup.action = #selector(deviceSelected)
        bufferPopup.action = #selector(settingsSelected)
        ratePopup.action = #selector(settingsSelected)
        pluginPopup.action = #selector(pluginSelected)
        devicePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true
        pluginPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true

        latencyLabel.textColor = .secondaryLabelColor
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let bufferRow = NSStackView(views: [bufferPopup, latencyLabel])
        bufferRow.spacing = 12

        loadGauge.levelIndicatorStyle = .continuousCapacity
        loadGauge.minValue = 0
        loadGauge.maxValue = 1
        loadGauge.warningValue = 0.7
        loadGauge.criticalValue = 0.9
        loadGauge.widthAnchor.constraint(equalToConstant: 170).isActive = true
        loadGauge.heightAnchor.constraint(equalToConstant: 14).isActive = true
        loadLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        loadLabel.textColor = .secondaryLabelColor
        loadLabel.toolTip = "Compute time / buffer duration. Above 100 %, the audio crackles (an “overrun”)."
        loadGauge.toolTip = loadLabel.toolTip
        let loadRow = NSStackView(views: [loadGauge, loadLabel])
        loadRow.spacing = 10

        let grid = NSGridView(views: [
            [label("Audio interface"), devicePopup],
            [label("Buffer"), bufferRow],
            [label("Buffer load"), loadRow],
            [label("Sample rate"), ratePopup],
            [label("AU plugin"), pluginPopup],
        ])
        grid.columnSpacing = 10
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing

        containerWidth = pluginContainer.widthAnchor.constraint(equalToConstant: 0)
        containerHeight = pluginContainer.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([containerWidth, containerHeight])
        pluginContainer.isHidden = true

        let separator = NSBox()
        separator.boxType = .separator

        content = NSStackView(views: [grid, statusLabel, separator, pluginContainer])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        separator.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32).isActive = true

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "SimplePlug"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = content
        fitWindow()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func fitWindow() {
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
    }

    // MARK: Interfaces / buffer / sample rate

    private var selectedInterface: AudioInterface? {
        interfaces.first { $0.uid == devicePopup.selectedItem?.representedObject as? String }
    }

    private func refreshInterfaces() {
        interfaces = HAL.interfaces()
        devicePopup.removeAllItems()
        for i in interfaces {
            devicePopup.addItem(withTitle: "\(i.name)  (\(i.inputs) in / \(i.outputs) out)")
            devicePopup.lastItem?.representedObject = i.uid
        }
        let wanted = defaults.string(forKey: Key.device)
            ?? HAL.defaultOutputDevice().flatMap { id in interfaces.first { $0.id == id }?.uid }
        if let idx = interfaces.firstIndex(where: { $0.uid == wanted }) {
            devicePopup.selectItem(at: idx)
        }
        devicePopup.isEnabled = !interfaces.isEmpty
        refreshDeviceSettings()
    }

    private func refreshDeviceSettings() {
        bufferPopup.removeAllItems()
        ratePopup.removeAllItems()
        guard let device = selectedInterface?.id else { return }

        let buffers = HAL.availableBuffers(device)
        for b in buffers {
            bufferPopup.addItem(withTitle: "\(b) samples")
            bufferPopup.lastItem?.tag = Int(b)
        }
        let savedBuffer = defaults.integer(forKey: Key.buffer)
        let currentBuffer = Int(HAL.bufferFrames(device) ?? 256)
        bufferPopup.selectItem(withTag: buffers.contains(UInt32(savedBuffer)) ? savedBuffer : currentBuffer)
        if bufferPopup.selectedItem == nil { bufferPopup.selectItem(at: 0) }

        let rates = HAL.availableRates(device)
        for r in rates {
            ratePopup.addItem(withTitle: String(format: "%g kHz", r / 1000))
            ratePopup.lastItem?.tag = Int(r)
        }
        let savedRate = defaults.integer(forKey: Key.rate)
        let currentRate = Int(HAL.sampleRate(device) ?? 48000)
        ratePopup.selectItem(withTag: rates.contains(Double(savedRate)) ? savedRate : currentRate)
        if ratePopup.selectedItem == nil { ratePopup.selectItem(at: 0) }
    }

    private func devicesChanged() {
        let before = selectedInterface?.uid
        refreshInterfaces()
        if selectedInterface?.uid != before || !engine.isRunning { restartAudio() }
    }

    @objc private func deviceSelected() {
        defaults.set(selectedInterface?.uid, forKey: Key.device)
        refreshDeviceSettings()
        restartAudio()
    }

    @objc private func settingsSelected() {
        defaults.set(bufferPopup.selectedItem?.tag, forKey: Key.buffer)
        defaults.set(ratePopup.selectedItem?.tag, forKey: Key.rate)
        restartAudio()
    }

    private func restartAudio() {
        guard let interface = selectedInterface else {
            engine.stop()
            latencyLabel.stringValue = ""
            setStatus("No audio interface with 2 inputs / 2 outputs found.", error: true)
            return
        }
        let buffer = UInt32(bufferPopup.selectedItem?.tag ?? 256)
        let rate = Double(ratePopup.selectedItem?.tag ?? 48000)
        do {
            try engine.start(device: interface.id, bufferFrames: buffer, sampleRate: rate)
            if let ms = HAL.roundTripMilliseconds(interface.id) {
                latencyLabel.stringValue = String(format: "latency ≈ %.1f ms", ms)
            }
            if micDenied {
                setStatus("Audio input access denied: System Settings › Privacy & Security › Microphone.", error: true)
            } else {
                setStatus("Running — inputs 1-2 → plugin → outputs 1-2", error: false)
            }
        } catch {
            latencyLabel.stringValue = ""
            setStatus(error.localizedDescription, error: true)
        }
    }

    /// Load gauge: instant rise, smoothed fall; the peak is held for 1.5 s.
    private func updateMeter() {
        guard engine.isRunning else {
            loadGauge.doubleValue = 0
            loadLabel.stringValue = ""
            shownLoad = 0
            return
        }
        guard let load = engine.readLoad() else { return }
        shownLoad = max(load.average, shownLoad * 0.85)
        let now = ProcessInfo.processInfo.systemUptime
        if load.peak >= peakHold || now - peakHoldSince > 1.5 {
            peakHold = load.peak
            peakHoldSince = now
        }
        loadGauge.doubleValue = min(shownLoad, 1)

        var text = String(format: "%3.0f %%  (peak %3.0f %%)", shownLoad * 100, peakHold * 100)
        let overloads = engine.overloads
        if overloads > 0 { text += "  ⚠︎ \(overloads) overrun\(overloads > 1 ? "s" : "")" }
        loadLabel.stringValue = text
        loadLabel.textColor = overloads > 0 ? .systemRed : .secondaryLabelColor
    }

    private func setStatus(_ text: String, error: Bool) {
        statusLabel.stringValue = (error ? "⚠︎ " : "● ") + text
        statusLabel.textColor = error ? .systemRed : .secondaryLabelColor
        statusLabel.toolTip = text
    }

    // MARK: Plugin

    private static func key(_ c: AVAudioUnitComponent) -> String {
        let d = c.audioComponentDescription
        return "\(d.componentType)-\(d.componentSubType)-\(d.componentManufacturer)"
    }

    private static func title(_ c: AVAudioUnitComponent) -> String {
        c.name.contains(c.manufacturerName) ? c.name : "\(c.manufacturerName): \(c.name)"
    }

    private func refreshPlugins() {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: 0,
                                             componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)
        components = AVAudioUnitComponentManager.shared().components(matching: desc)
            .sorted { Self.title($0).localizedCaseInsensitiveCompare(Self.title($1)) == .orderedAscending }
        desc.componentType = 0
        pluginPopup.removeAllItems()
        pluginPopup.addItem(withTitle: "None (pass-through)")
        pluginPopup.menu?.addItem(.separator())
        for c in components { pluginPopup.addItem(withTitle: Self.title(c)) }
    }

    @objc private func pluginSelected() {
        let index = pluginPopup.indexOfSelectedItem - 2
        let component = components.indices.contains(index) ? components[index] : nil
        defaults.set(component.map(Self.key), forKey: Key.plugin)
        Task { await loadPlugin(component) }
    }

    private func loadPlugin(_ component: AVAudioUnitComponent?) async {
        pluginPopup.isEnabled = false
        defer { pluginPopup.isEnabled = true }

        savePluginState()
        engine.stop()
        pluginContainer.subviews.forEach { $0.removeFromSuperview() }
        pluginContainer.isHidden = true
        pluginKey = nil
        engine.unloadPlugin()
        fitWindow()

        if let component {
            setStatus("Loading “\(component.name)”…", error: false)
            do {
                let unit = try await engine.loadPlugin(component.audioComponentDescription)
                pluginKey = Self.key(component)
                if let data = defaults.data(forKey: Key.state(pluginKey!)),
                   let state = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    unit.auAudioUnit.fullState = state
                }
                show(await PluginView.make(for: unit))
            } catch {
                setStatus("Couldn't load the plugin: \(error.localizedDescription)", error: true)
                return
            }
        }
        restartAudio()
    }

    private func show(_ view: NSView) {
        let size = view.frame.size == .zero ? NSSize(width: 400, height: 200) : view.frame.size
        let width = max(size.width, 480 - 32)
        containerWidth.constant = width
        containerHeight.constant = size.height
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.minXMargin, .maxXMargin]
        view.frame = NSRect(x: (width - size.width) / 2, y: 0, width: size.width, height: size.height)
        pluginContainer.addSubview(view)
        pluginContainer.isHidden = false
        fitWindow()
    }

    private func savePluginState() {
        guard let key = pluginKey, let state = engine.plugin?.auAudioUnit.fullState,
              let data = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0) else { return }
        defaults.set(data, forKey: Key.state(key))
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
