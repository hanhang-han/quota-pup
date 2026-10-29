import AppKit

struct SpriteFrame: Decodable {
    let rows: [String]
    let durationMs: Int
}
struct Sprite: Decodable {
    let id: String
    let label: String
    let rows: [String]
    let frames: [SpriteFrame]?
}
struct SpriteSheet: Decodable {
    let width: Int
    let height: Int
    let states: [Sprite]
}
let resourceURL = Bundle.main.resourceURL!
let sprites = try! JSONDecoder().decode(SpriteSheet.self, from: Data(contentsOf: resourceURL.appendingPathComponent("sprites.json")))

func petStateID(for remaining: Double) -> String {
    if remaining <= 0 { return "sleep" }
    if remaining <= 15 { return "rest" }
    if remaining <= 40 { return "sit" }
    if remaining <= 70 { return "steady" }
    return "bright"
}

func drawDog(_ sprite: Sprite, in rect: NSRect, template: Bool, unknown: Bool = false, frameIndex: Int = 0) {
    let cell = floor(min(rect.width / CGFloat(sprites.width), rect.height / CGFloat(sprites.height)))
    let ox = rect.minX + floor((rect.width - CGFloat(sprites.width) * cell) / 2)
    let oy = rect.minY + floor((rect.height - CGFloat(sprites.height) * cell) / 2)
    let palette: [Character: NSColor] = [
        "o": NSColor(srgbRed: 0.26, green: 0.21, blue: 0.18, alpha: 1),
        "b": NSColor(srgbRed: 0.85, green: 0.63, blue: 0.38, alpha: 1),
        "c": NSColor(srgbRed: 1, green: 0.945, blue: 0.81, alpha: 1),
        "e": NSColor(srgbRed: 0.21, green: 0.17, blue: 0.15, alpha: 1)
    ]
    NSGraphicsContext.current?.imageInterpolation = .none
    NSGraphicsContext.current?.shouldAntialias = false
    let rows = sprite.frames.flatMap { $0.isEmpty ? nil : $0[frameIndex % $0.count].rows } ?? sprite.rows
    for (y, row) in rows.enumerated() {
        for (x, pixel) in row.enumerated() {
            guard pixel != ".", !(template && pixel == "c") else { continue }
            (template ? NSColor.black : (palette[pixel] ?? .clear)).setFill()
            NSRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(sprites.height - 1 - y) * cell,
                   width: cell, height: cell).fill()
        }
    }
    if unknown {
        NSGraphicsContext.current?.shouldAntialias = true
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: template ? 9 : 20, weight: .bold),
            .foregroundColor: template ? NSColor.black : NSColor.secondaryLabelColor
        ]
        NSString(string: "?").draw(at: NSPoint(x: rect.maxX - (template ? 7 : 28), y: rect.maxY - (template ? 11 : 28)), withAttributes: attrs)
    }
}

final class DogView: NSView {
    var sprite = sprites.states[0]
    var unknown = true
    var frameIndex = 0
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawDog(sprite, in: bounds, template: false, unknown: unknown, frameIndex: frameIndex)
    }
}

final class PupController: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    let dog = DogView(frame: NSRect(x: 34, y: 128, width: 192, height: 126))
    let title = NSTextField(labelWithString: "认识一下，余粮")
    let number = NSTextField(labelWithString: "—%")
    let detail = NSTextField(labelWithString: "正在看看还有多少精力…")
    let syncLabel = NSTextField(labelWithString: "正在同步")
    var remaining: Double?
    var currentWindow: RateWindow?
    var fetching = false
    var timer: Timer?
    var animationTimer: Timer?
    var animationStart = ProcessInfo.processInfo.systemUptime
    var currentSpriteID = ""
    var lastAnimationKey = ""
    var iconCache: [String: NSImage] = [:]
    var lastFetchSucceeded = false
    let quotaClient = QuotaClient()
    var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.setAccessibilityLabel("余粮，正在读取 Codex 额度")
        buildPopover()
        render()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        if !CommandLine.arguments.contains("--background") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.togglePopover() }
        }
    }

    func buildPopover() {
        let controller = NSViewController()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 300))
        view.wantsLayer = true
        let brand = NSTextField(labelWithString: "余 粮")
        brand.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        brand.textColor = .secondaryLabelColor
        brand.frame = NSRect(x: 20, y: 270, width: 80, height: 16)
        view.addSubview(brand)
        view.addSubview(dog)
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        title.alignment = .center
        title.frame = NSRect(x: 12, y: 100, width: 236, height: 25)
        view.addSubview(title)
        number.font = NSFont.monospacedDigitSystemFont(ofSize: 29, weight: .medium)
        number.alignment = .center
        number.frame = NSRect(x: 12, y: 63, width: 236, height: 37)
        view.addSubview(number)
        detail.font = NSFont.systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.frame = NSRect(x: 12, y: 43, width: 236, height: 18)
        view.addSubview(detail)
        syncLabel.font = NSFont.systemFont(ofSize: 10)
        syncLabel.textColor = .tertiaryLabelColor
        syncLabel.alignment = .center
        syncLabel.frame = NSRect(x: 35, y: 14, width: 190, height: 16)
        view.addSubview(syncLabel)
        let more = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "更多")!, target: self, action: #selector(showMore(_:)))
        more.isBordered = false
        more.frame = NSRect(x: 216, y: 264, width: 27, height: 25)
        view.addSubview(more)
        controller.view = view
        popover.contentViewController = controller
        popover.contentSize = view.frame.size
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        render()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showMore(_ sender: NSButton) {
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "刷新额度", action: #selector(manualRefresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = !fetching
        menu.addItem(refreshItem)
        if let value = remaining {
            let item = NSMenuItem(title: "最近读数：剩余 \(Int(value.rounded()))%", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出余粮", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
    }

    @objc func quit() { NSApp.terminate(nil) }
    @objc func manualRefresh() { refresh() }
    @objc func accessibilityChanged() { animate() }

    func animate() {
        animationTimer?.invalidate()
        animationTimer = nil
        let state = sprites.states.first { $0.id == petStateID(for: remaining ?? 80) } ?? sprites.states[0]
        let unknown = !lastFetchSucceeded
        if currentSpriteID != state.id {
            currentSpriteID = state.id
            animationStart = ProcessInfo.processInfo.systemUptime
        }
        var frameIndex = 0
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let frames = state.frames, !frames.isEmpty {
            let durations = frames.map { max(80, $0.durationMs) }
            let total = durations.reduce(0, +)
            var elapsed = Int((ProcessInfo.processInfo.systemUptime - animationStart) * 1000) % total
            for (index, duration) in durations.enumerated() {
                if elapsed < duration {
                    frameIndex = index
                    // Wake for the next actual pose change instead of polling at a fixed frame rate.
                    let nextFrame = Timer(timeInterval: max(0.016, Double(duration - elapsed) / 1000), repeats: false) { [weak self] _ in
                        self?.animate()
                    }
                    nextFrame.tolerance = 0.015
                    RunLoop.main.add(nextFrame, forMode: .common)
                    animationTimer = nextFrame
                    break
                }
                elapsed -= duration
            }
        }
        let key = "\(state.id):\(frameIndex):\(unknown)"
        guard key != lastAnimationKey else { return }
        lastAnimationKey = key
        let image: NSImage
        if let cached = iconCache[key] {
            image = cached
        } else {
            image = NSImage(size: NSSize(width: 24, height: 18), flipped: false) { rect in
                drawDog(state, in: rect, template: true, unknown: unknown, frameIndex: frameIndex)
                return true
            }
            image.isTemplate = true
            iconCache[key] = image
        }
        statusItem.button?.image = image
        dog.sprite = state
        dog.unknown = unknown
        dog.frameIndex = frameIndex
        dog.needsDisplay = true
    }

    func render() {
        let state = sprites.states.first { $0.id == petStateID(for: remaining ?? 80) } ?? sprites.states[0]
        let unknown = !lastFetchSucceeded
        animate()
        let cadence: String
        if let window = currentWindow {
            cadence = window.windowMinutes >= 10080 ? "每周额度" : (window.windowMinutes >= 1440 ? "周期额度" : "短时额度")
        } else { cadence = "Codex 额度" }
        let reset: String
        if let raw = currentWindow?.resetsAt, let date = ISO8601DateFormatter().date(from: raw) {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "zh_CN")
            fmt.dateFormat = "M月d日 HH:mm"
            reset = fmt.string(from: date) + " 恢复"
        } else { reset = "恢复时间暂未提供" }
        if unknown {
            title.stringValue = fetching && remaining == nil ? "正在认识你的额度" : "暂时看不到精力"
            detail.stringValue = lastError ?? (remaining == nil ? "稍后会自动再看看" : "保留上次读数，等待重新同步")
            number.stringValue = remaining.map { "上次 \(Int($0.rounded()))%" } ?? "—%"
        } else {
            title.stringValue = state.label
            detail.stringValue = reset
            number.stringValue = "剩余 \(Int((remaining ?? 0).rounded()))%"
        }
        number.setAccessibilityLabel(unknown ? "上次同步的剩余额度" : "\(cadence)剩余百分比")
        let tooltip = unknown ? "余粮：额度暂未同步，不能判断剩余量" : "\(cadence)剩余 \(Int((remaining ?? 0).rounded()))%，\(reset)"
        statusItem.button?.toolTip = tooltip
        statusItem.button?.setAccessibilityLabel(tooltip)
        dog.setAccessibilityElement(true)
        dog.setAccessibilityLabel(tooltip)
    }

    func refresh() {
        guard !fetching else { return }
        fetching = true
        syncLabel.stringValue = "正在同步"
        Task { [weak self] in
            guard let self else { return }
            let result: Result<RateWindow, Error>
            do { result = .success(try await self.quotaClient.fetch()) }
            catch { result = .failure(error) }
            await MainActor.run {
                self.fetching = false
                let chosen: RateWindow?
                switch result {
                case .success(let window):
                    chosen = window
                    self.lastFetchSucceeded = true
                    self.lastError = nil
                    self.currentWindow = window
                    self.remaining = max(0, min(100, 100 - window.usedPercent))
                    self.syncLabel.stringValue = "刚刚同步 · 每分钟看看"
                case .failure(let error):
                    chosen = nil
                    self.lastFetchSucceeded = false
                    self.lastError = (error as? QuotaError)?.errorDescription ?? "暂时无法同步额度"
                    self.syncLabel.stringValue = "同步暂停 · 稍后重试"
                }
                self.render()
                // Prototype diagnostics: current quota only, no account or credential data.
                var report: [String: Any] = [
                    "status": chosen == nil ? "unavailable" : "ok",
                    "checkedAt": ISO8601DateFormatter().string(from: Date()),
                    "state": chosen == nil ? "unknown" : petStateID(for: self.remaining ?? 0)
                ]
                report["displayedRemaining"] = self.number.stringValue
                report["animationFrames"] = sprites.states.first { $0.id == self.currentSpriteID }?.frames?.count ?? 1
                report["source"] = "direct-openai"
                if let result = chosen {
                    report["remainingPercent"] = self.remaining
                    report["windowMinutes"] = result.windowMinutes
                    report["resetsAt"] = result.resetsAt
                }
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    let destination = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("runtime-status.json")
                    try? data.write(to: destination, options: .atomic)
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = PupController()
app.delegate = delegate
app.run()
