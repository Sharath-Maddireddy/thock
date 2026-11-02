// Thock: menu-bar app that plays real mechanical keyboard recordings as you type.
// Sounds: Mechvibes sound packs (MIT), see sounds/LICENSE-mechvibes.
import Cocoa
import AVFoundation

let packs = [("brown", "Cherry MX Brown"), ("blue", "Cherry MX Blue"), ("cream", "NovelKeys Cream"), ("topre", "Topre"), ("oreo", "EG Oreo")]

// macOS virtual keycode -> Mechvibes (iohook / PC scancode) key id, US layout.
let scancodes: [Int64: Int] = [
    0: 30, 1: 31, 2: 32, 3: 33, 4: 35, 5: 34, 6: 44, 7: 45, 8: 46, 9: 47, 11: 48, 12: 16, 13: 17, 14: 18, 15: 19,
    16: 21, 17: 20, 18: 2, 19: 3, 20: 4, 21: 5, 22: 7, 23: 6, 24: 13, 25: 10, 26: 8, 27: 12, 28: 9, 29: 11, 30: 27,
    31: 24, 32: 22, 33: 26, 34: 23, 35: 25, 36: 28, 37: 38, 38: 36, 39: 40, 40: 37, 41: 39, 42: 43, 43: 51, 44: 53,
    45: 49, 46: 50, 47: 52, 48: 15, 49: 57, 50: 41, 51: 14, 53: 1, 54: 3676, 55: 3675, 56: 42, 57: 58, 58: 56,
    59: 29, 60: 54, 61: 3640, 62: 3613, 76: 3612, 122: 59, 120: 60, 99: 61, 118: 62, 96: 63, 97: 64, 98: 65,
    100: 66, 101: 67, 109: 68, 103: 87, 111: 88, 117: 3667, 115: 3655, 119: 3663, 116: 3657, 121: 3665,
    123: 57419, 124: 57421, 125: 57424, 126: 57416,
]

// One long recording of a whole keyboard, sliced into a buffer per key via config.json [start_ms, length_ms].
struct Pack {
    var keys: [Int: AVAudioPCMBuffer] = [:]

    init(dir: URL) throws {
        let file = try AVAudioFile(forReading: dir.appendingPathComponent("sound.caf"))
        let sprite = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: sprite)
        // Packs were recorded at very different levels; peak-normalize so switching packs keeps the same loudness.
        let samples = UnsafeMutableBufferPointer(start: sprite.floatChannelData![0], count: Int(sprite.frameLength))
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        if peak > 0 { for i in samples.indices { samples[i] *= 0.9 / peak } }
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("config.json"))) as! [String: Any]
        let msToFrame = file.processingFormat.sampleRate / 1000
        for (key, value) in config["defines"] as! [String: Any] {
            guard let span = value as? [Double], span.count == 2 else { continue } // some packs leave unused keys null
            let start = min(Int(span[0] * msToFrame), Int(sprite.frameLength))
            let count = min(Int(span[1] * msToFrame), Int(sprite.frameLength) - start)
            guard count > 0, let id = Int(key) else { continue }
            let buf = AVAudioPCMBuffer(pcmFormat: sprite.format, frameCapacity: AVAudioFrameCount(count))!
            buf.frameLength = AVAudioFrameCount(count)
            buf.floatChannelData![0].update(from: sprite.floatChannelData![0] + start, count: count)
            keys[id] = buf
        }
    }

    // Unknown keys fall back to a random letter so every press still clicks.
    func sound(keycode: Int64) -> AVAudioPCMBuffer {
        if let id = scancodes[keycode], let b = keys[id] { return b }
        return keys[Int.random(in: 30...38)] ?? keys.values.first!
    }
}

func loadPacks(from root: URL) throws -> [String: Pack] {
    try Dictionary(uniqueKeysWithValues: packs.map { ($0.0, try Pack(dir: root.appendingPathComponent($0.0))) })
}

final class App: NSObject, NSApplicationDelegate {
    let engine = AVAudioEngine()
    var players: [AVAudioPlayerNode] = []
    var nextPlayer = 0
    var loaded: [String: Pack] = [:]
    var current = UserDefaults.standard.string(forKey: "pack") ?? "brown"
    var muted = false
    var heldModifiers: Set<Int64> = []
    var keysHeard = 0
    let countLabel = NSTextField(labelWithString: "Keys heard: 0")
    var tap: CFMachPort?
    var idleStop: Timer?
    var statusItem: NSStatusItem!
    let keyStatus = NSMenuItem(title: "Keyboard: waiting for Input Monitoring…", action: nil, keyEquivalent: "")
    let audioStatus = NSMenuItem(title: "Audio: starting…", action: nil, keyEquivalent: "")
    let keyLabel = NSTextField(labelWithString: "")
    let audioLabel = NSTextField(labelWithString: "")
    let picker = NSPopUpButton(frame: .zero, pullsDown: false)
    let volume = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    var window: NSWindow!

    func applicationDidFinishLaunching(_: Notification) {
        loaded = try! loadPacks(from: Bundle.main.resourceURL!.appendingPathComponent("sounds"))
        if loaded[current] == nil { current = packs[0].0 }
        let format = loaded[packs[0].0]!.keys.values.first!.format // all packs converted to mono 44.1 kHz
        for _ in 0..<16 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        buildWindow()
        buildMenu()
        setStatus(key: keyStatus.title, audio: audioStatus.title)
        startAudio()
        // Engine stops when the output device changes (e.g. headphones plugged in).
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in self?.startAudio() }

        if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }
        // Keep retrying until Input Monitoring is granted; no relaunch needed.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            if CGPreflightListenEventAccess(), self?.installTap() == true {
                timer.invalidate()
                self?.setStatus(key: "Keyboard: connected ✓")
            }
        }.fire()
        // Stay quiet at login unless something needs attention; opening Thock by hand always shows the window.
        if !launchedAtLogin() || tap == nil || audioStatus.title != "Audio: ok ✓" { showWindow() }
    }

    func launchedAtLogin() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌨︎"
        let menu = NSMenu()
        menu.addItem(keyStatus)
        menu.addItem(audioStatus)
        menu.addItem(withTitle: "Show Window", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(.separator())
        for (id, title) in packs {
            let item = menu.addItem(withTitle: title, action: #selector(choosePack(_:)), keyEquivalent: "")
            item.representedObject = id
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Mute", action: #selector(toggleMute(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Thock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        syncPackUI()
    }

    func buildWindow() {
        let title = NSTextField(labelWithString: "Thock is running")
        title.font = .boldSystemFont(ofSize: 15)
        picker.addItems(withTitles: packs.map { $0.1 })
        picker.target = self
        picker.action = #selector(pickPack(_:))
        volume.doubleValue = UserDefaults.standard.object(forKey: "volume") as? Double ?? 1
        engine.mainMixerNode.outputVolume = Float(volume.doubleValue)
        volume.target = self
        volume.action = #selector(volumeChanged)
        volume.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let volumeRow = NSStackView(views: [NSTextField(labelWithString: "Volume"), volume])
        let test = NSButton(title: "Play Test Sound", target: self, action: #selector(testSound))
        let hint = NSTextField(wrappingLabelWithString: "You can close this window; Thock keeps running. Open Thock again from Applications to see it, or use the ⌨︎ icon at the top-right of the screen.")
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 340
        let stack = NSStackView(views: [title, keyLabel, audioLabel, countLabel, picker, volumeRow, test, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Thock"
        window.contentView = stack
        window.isReleasedWhenClosed = false
    }

    @objc func showWindow() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showWindow()
        return false
    }

    func setStatus(key: String? = nil, audio: String? = nil) {
        if let key { keyStatus.title = key; keyLabel.stringValue = key }
        if let audio { audioStatus.title = audio; audioLabel.stringValue = audio }
    }

    func startAudio() {
        do {
            try engine.start()
            players.forEach { $0.play() }
            setStatus(audio: "Audio: ok ✓")
            armIdleStop()
        } catch {
            setStatus(audio: "Audio: failed (\(error.localizedDescription))")
        }
    }

    // A running audio engine stops the Mac from idle-sleeping, so shut it off when nobody is typing.
    func armIdleStop() {
        idleStop?.invalidate()
        idleStop = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in self?.engine.pause() } // pause, not stop: stop leaves the player nodes silent after restart
    }

    func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.flagsChanged.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                        eventsOfInterest: mask, callback: { _, type, event, refcon in
            let app = Unmanaged<App>.fromOpaque(refcon!).takeUnretainedValue()
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let t = app.tap { CGEvent.tapEnable(tap: t, enable: true) }
            case .flagsChanged: // modifiers (shift, cmd…) toggle; click only on the press
                if app.heldModifiers.remove(code) == nil { app.heldModifiers.insert(code); app.heard(keycode: code) }
            case .keyDown where event.getIntegerValueField(.keyboardEventAutorepeat) == 0:
                app.heard(keycode: code)
            default: break
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func heard(keycode: Int64) {
        keysHeard += 1
        countLabel.stringValue = "Keys heard: \(keysHeard)"
        play(keycode: keycode)
    }

    func play(keycode: Int64) {
        guard !muted else { return }
        if engine.isRunning { armIdleStop() } else { startAudio() }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.scheduleBuffer(loaded[current]!.sound(keycode: keycode), at: nil, options: .interrupts)
        if !p.isPlaying { p.play() }
    }

    @objc func testSound() {
        for (i, code) in ([17, 4, 14, 49, 38] as [Int64]).enumerated() { // "the j" typed
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) { self.play(keycode: code) }
        }
    }

    func setPack(_ id: String) {
        current = id
        UserDefaults.standard.set(id, forKey: "pack")
        syncPackUI()
    }

    func syncPackUI() {
        statusItem.menu?.items.forEach { if let id = $0.representedObject as? String { $0.state = id == current ? .on : .off } }
        picker.selectItem(at: packs.firstIndex { $0.0 == current } ?? 0)
    }

    @objc func volumeChanged() {
        engine.mainMixerNode.outputVolume = Float(volume.doubleValue)
        UserDefaults.standard.set(volume.doubleValue, forKey: "volume")
    }

    @objc func choosePack(_ item: NSMenuItem) { setPack(item.representedObject as! String) }
    @objc func pickPack(_ picker: NSPopUpButton) { setPack(packs[picker.indexOfSelectedItem].0) }

    @objc func toggleMute(_ item: NSMenuItem) {
        muted.toggle()
        item.state = muted ? .on : .off
        statusItem.button?.appearsDisabled = muted
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--selftest") {
    let loaded = try! loadPacks(from: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    for (id, pack) in loaded {
        let missing = scancodes.values.filter { pack.keys[$0] == nil }
        precondition(missing.isEmpty, "\(id) missing keys \(missing)")
        for code: Int64 in [0, 49, 36, 51, 56, 55, 123, 999] {
            let b = pack.sound(keycode: code)
            precondition(b.frameLength > 1000 && b.format.channelCount == 1, "\(id) bad buffer for \(code)")
        }
        precondition(pack.sound(keycode: 0) !== pack.sound(keycode: 49), "\(id): A and Space should differ")
    }
    print("selftest ok: \(loaded.keys.sorted())")
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
