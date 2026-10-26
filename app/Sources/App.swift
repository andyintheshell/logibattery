//  App.swift
//  The menu bar item, its dropdown, and the drawing both are built from.
//
//  The status item shows one [icon][mini bar] pair per paired device; the
//  dropdown shows the same breakdown as ../mxbattery, rendered natively.

import AppKit
import ServiceManagement

// MARK: - Palette

/// Bar colour by urgency. `full` and `good` share a colour on purpose: the
/// bar's length already separates 81-100% from 31-80%, so colour only needs to
/// carry urgency.
func bandColor(_ band: String) -> NSColor {
    switch band {
    case "full", "good": return .systemGreen
    case "low": return .systemOrange
    case "critical": return .systemRed
    default: return .systemGray
    }
}

/// A device as the UI needs it: the reading (nil if it did not answer) plus
/// everything derived from it.
struct DeviceStatus {
    let name: String
    let battery: String
    let reading: BatteryReading?
    let estimate: Estimate
    /// True when the slot is paired but the device never answered.
    var isAsleep: Bool { reading == nil }
}

// MARK: - Bar drawing

/// Draw a charge bar that refuses to fake precision: the solid run is charge we
/// can prove is present, the translucent run is the band the true value is
/// hiding in, and the empty track is definitely consumed. For a fine-grained
/// gauge the translucent run is zero-width and the bar is exact.
func drawChargeBar(in rect: NSRect, socLow: Int, socHigh: Int,
                   color: NSColor, asleep: Bool = false) {
    let radius = min(rect.height / 2, 3)
    let track = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    // `quaternaryLabelColor` is already faint. Forcing an absolute alpha on it
    // made the track mid-grey, which blended with the translucent run into a
    // *darker* colour - reading as "less charge" when it means "not known".
    NSColor.quaternaryLabelColor.setFill()
    track.fill()
    guard !asleep else { return }

    let lower = rect.width * CGFloat(socLow) / 100
    let upper = rect.width * CGFloat(socHigh) / 100
    NSGraphicsContext.saveGraphicsState()
    track.addClip()
    color.setFill()
    NSRect(x: rect.minX, y: rect.minY, width: lower, height: rect.height).fill()
    color.withAlphaComponent(0.38).setFill()
    NSRect(x: rect.minX + lower, y: rect.minY,
           width: max(0, upper - lower), height: rect.height).fill()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Status item image

/// SF Symbol for a device. Falls back to a bare bar when the symbol is missing,
/// which is also what the "Show Device Icons" toggle selects.
func deviceSymbolName(_ deviceName: String) -> String {
    let name = deviceName.lowercased()
    if name.contains("k860") || name.contains("keyboard") || name.contains("keys") {
        return "keyboard"
    }
    if name.contains("mouse") || name.contains("ergo") || name.contains("mx ") {
        return "computermouse"
    }
    return "dot.radiowaves.left.and.right"
}

private func symbolImage(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
        return nil
    }
    // `applying`, not a second `withSymbolConfiguration`: chaining would replace
    // the point size with the palette's defaults.
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let sized = base.withSymbolConfiguration(config) else { return nil }
    sized.isTemplate = false
    return sized
}

/// Draws a symbol scaled to fit a fixed box, centred. The box is what makes the
/// layout arithmetic exact - see `statusImage`.
private func drawSymbol(_ name: String, in box: NSRect, color: NSColor) {
    guard let symbol = symbolImage(name, pointSize: box.height, color: color) else { return }
    let size = symbol.size
    guard size.width > 0, size.height > 0 else { return }
    let scale = min(box.width / size.width, box.height / size.height)
    let fitted = NSSize(width: size.width * scale, height: size.height * scale)
    symbol.draw(in: NSRect(x: box.midX - fitted.width / 2,
                           y: box.midY - fitted.height / 2,
                           width: fitted.width, height: fitted.height))
}

enum StatusLayout {
    static let symbolWidth: CGFloat = 15
    static let symbolHeight: CGFloat = 13
    static let symbolGap: CGFloat = 2.5
    static let barWidth: CGFloat = 16
    static let barHeight: CGFloat = 6
    static let deviceGap: CGFloat = 7
    static let height: CGFloat = 18
}

/// The menu bar image: `[icon][bar]` per device, left to right.
///
/// Every element gets a fixed box, so the width reserved up front is exactly the
/// width drawn. Sizing this from the symbol images instead is a trap: SF Symbols
/// are measured in *font* point size, and a glyph like `keyboard` is much wider
/// than its point size, so the images silently overran the canvas and clipped
/// the right-hand end off every bar - including, on a coarse gauge, the entire
/// "unknown" run.
func statusImage(devices: [DeviceStatus], showIcons: Bool) -> NSImage {
    let layout = StatusLayout.self
    let perDevice = (showIcons ? layout.symbolWidth + layout.symbolGap : 0) + layout.barWidth
    let width = max(CGFloat(devices.count) * perDevice
                    + CGFloat(max(0, devices.count - 1)) * layout.deviceGap,
                    perDevice)

    let image = NSImage(size: NSSize(width: width, height: layout.height))
    image.lockFocus()
    defer { image.unlockFocus() }

    var x: CGFloat = 0
    for (index, device) in devices.enumerated() {
        if index > 0 { x += layout.deviceGap }
        let band = device.reading?.band ?? ""
        let color = device.isAsleep ? NSColor.tertiaryLabelColor : bandColor(band)

        if showIcons {
            drawSymbol(deviceSymbolName(device.name),
                       in: NSRect(x: x, y: (layout.height - layout.symbolHeight) / 2,
                                  width: layout.symbolWidth, height: layout.symbolHeight),
                       color: color)
            x += layout.symbolWidth + layout.symbolGap
        }

        drawChargeBar(in: NSRect(x: x, y: (layout.height - layout.barHeight) / 2,
                                 width: layout.barWidth, height: layout.barHeight),
                      socLow: device.reading?.socLow ?? 0,
                      socHigh: device.reading?.socHigh ?? 0,
                      color: color,
                      asleep: device.isAsleep)
        x += layout.barWidth
    }
    return image
}

// MARK: - Dropdown block

/// One device's block in the dropdown, drawn as a single view so the layout is
/// fully deterministic (NSMenuItem custom views do not auto-size to fit). The
/// view is flipped, so layout runs top-down with a single increasing cursor,
/// and measurement and drawing walk the same metrics.
final class DeviceBlockView: NSView {
    static let blockWidth: CGFloat = 330
    private static let margin: CGFloat = 14

    private enum Metrics {
        static let topPad: CGFloat = 10
        static let bottomPad: CGFloat = 10
        static let header: CGFloat = 17
        static let bar: CGFloat = 10
        static let band: CGFloat = 15
        static let row: CGFloat = 17
        static let gapHeaderBar: CGFloat = 7
        static let gapBarBand: CGFloat = 7
        static let gapBandRows: CGFloat = 11
        static let gapRowsNote: CGFloat = 9
    }

    private let device: DeviceStatus
    private let rows: [(String, String)]
    private let footnote: NSAttributedString?

    init(device: DeviceStatus) {
        self.device = device
        rows = Self.detailRows(for: device)
        footnote = Self.footnote(for: device)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.blockWidth, height: 10))
        setFrameSize(NSSize(width: Self.blockWidth, height: contentHeight()))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private static var contentWidth: CGFloat { blockWidth - margin * 2 }

    // MARK: content

    private static func detailRows(for device: DeviceStatus) -> [(String, String)] {
        guard let _ = device.reading else { return [] }
        var rows: [(String, String)] = []
        for scenario in device.estimate.scenarios {
            rows.append((scenario.label,
                         Fmt.range(daysLow: scenario.low, daysHigh: scenario.high)))
        }
        if let months = device.estimate.monthsOff {
            rows.append(("switched off", Fmt.months(months)))
        }
        if let low = device.estimate.activeHoursLow,
           let high = device.estimate.activeHoursHigh {
            rows.append(("active movement", "~" + Fmt.pair(low: low, high: high, unit: "h")))
        }
        if let percent = device.estimate.selfPercentPerMonth {
            rows.append(("self-discharge", String(format: "%.2f%%/month", percent)))
        }
        if rows.isEmpty {
            rows.append(("runtime", "no model for this device"))
        }
        return rows
    }

    /// The caveats that keep the numbers above honest, joined into one wrapped
    /// paragraph rather than a column, which would not fit at this width.
    private static func footnote(for device: DeviceStatus) -> NSAttributedString? {
        guard let reading = device.reading else {
            return NSAttributedString(
                string: "Press a key or move it, then choose Refresh Now.",
                attributes: footnoteAttributes)
        }
        var parts: [String] = []
        if reading.coarse {
            let levels = reading.gaugeLevels.map(String.init) ?? "?"
            parts.append("\(levels)-level gauge, so the shaded run is the uncertainty")
        } else {
            parts.append("fine-grained gauge, so the bar is exact")
        }
        if let low = device.estimate.selfShareLow,
           let high = device.estimate.selfShareHigh {
            // %.1f, not %g: the raw values carry full float precision and %g
            // happily printed "5.48208-17.28%".
            parts.append("self-discharge eats \(String(format: "%.1f", low))\(Fmt.enDash)"
                         + "\(String(format: "%.1f", high))% of a charge")
        }
        if device.estimate.activeHoursLow != nil {
            parts.append("active movement is fitted, not measured")
        }
        return NSAttributedString(string: parts.joined(separator: " \u{00b7} "),
                                  attributes: footnoteAttributes)
    }

    private static var footnoteAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.tertiaryLabelColor]
    }

    // MARK: measurement

    private func footnoteRect(at y: CGFloat) -> NSRect? {
        guard let footnote else { return nil }
        let bounds = footnote.boundingRect(
            with: NSSize(width: Self.contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin])
        return NSRect(x: Self.margin, y: y, width: Self.contentWidth,
                      height: ceil(bounds.height))
    }

    private func contentHeight() -> CGFloat {
        var height = Metrics.topPad + Metrics.header
        height += Metrics.gapHeaderBar + Metrics.bar
        height += Metrics.gapBarBand + Metrics.band
        if !rows.isEmpty {
            height += Metrics.gapBandRows + CGFloat(rows.count) * Metrics.row
        }
        if let rect = footnoteRect(at: 0) {
            height += Metrics.gapRowsNote + rect.height
        }
        return height + Metrics.bottomPad
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        let width = Self.blockWidth
        var y = Metrics.topPad

        let name = NSAttributedString(string: device.name, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        let battery = NSAttributedString(string: device.battery, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        name.draw(at: NSPoint(x: Self.margin, y: y))
        battery.draw(at: NSPoint(x: width - Self.margin - battery.size().width, y: y + 2))
        y += Metrics.header

        y += Metrics.gapHeaderBar
        let color = device.isAsleep ? NSColor.tertiaryLabelColor
                                    : bandColor(device.reading?.band ?? "")
        drawChargeBar(in: NSRect(x: Self.margin, y: y, width: Self.contentWidth,
                                 height: Metrics.bar),
                      socLow: device.reading?.socLow ?? 0,
                      socHigh: device.reading?.socHigh ?? 0,
                      color: color,
                      asleep: device.isAsleep)
        y += Metrics.bar

        y += Metrics.gapBarBand
        let bandText: String
        let rangeText: String
        let statusText: String
        if let reading = device.reading {
            bandText = reading.band
            rangeText = reading.coarse
                ? "\(reading.socLow)\(Fmt.enDash)\(reading.socHigh)%"
                : "\(reading.reportedPercent)%"
            statusText = reading.statusName
        } else {
            bandText = "no reading"
            rangeText = ""
            statusText = "asleep or switched off"
        }
        NSAttributedString(string: bandText, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: device.isAsleep ? NSColor.secondaryLabelColor : color,
        ]).draw(at: NSPoint(x: Self.margin, y: y))
        let status = NSAttributedString(string: [rangeText, statusText]
            .filter { !$0.isEmpty }.joined(separator: "  \u{00b7}  "),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        status.draw(at: NSPoint(x: width - Self.margin - status.size().width, y: y + 1))
        y += Metrics.band

        if !rows.isEmpty {
            y += Metrics.gapBandRows
            let labelFont = NSFont.systemFont(ofSize: 11)
            let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            for (label, value) in rows {
                NSAttributedString(string: label, attributes: [
                    .font: labelFont, .foregroundColor: NSColor.secondaryLabelColor,
                ]).draw(at: NSPoint(x: Self.margin, y: y + 1))
                let valueText = NSAttributedString(string: value, attributes: [
                    .font: valueFont, .foregroundColor: NSColor.labelColor,
                ])
                valueText.draw(at: NSPoint(x: width - Self.margin - valueText.size().width,
                                           y: y + 1))
                y += Metrics.row
            }
        }

        if let footnote, let rect = footnoteRect(at: y + Metrics.gapRowsNote) {
            footnote.draw(with: rect, options: [.usesLineFragmentOrigin])
        }
    }
}

// MARK: - Menu bar controller

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var devices: [DeviceStatus] = []
    private var lastUpdated: Date?
    private var refreshTimer: Timer?
    private let readQueue = DispatchQueue(label: "hidpp.read", qos: .utility)

    var refreshInterval: TimeInterval {
        get {
            let stored = UserDefaults.standard.double(forKey: "refreshInterval")
            return stored > 0 ? stored : 300
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "refreshInterval")
            scheduleTimer()
        }
    }

    var showIcons: Bool {
        get { UserDefaults.standard.object(forKey: "showIcons") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "showIcons")
            updateStatusItem()
        }
    }

    override init() {
        super.init()
        statusItem.button?.imagePosition = .imageOnly
        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()
        refresh()
        scheduleTimer()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(woke),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: reading

    @objc func refresh() {
        readQueue.async { [weak self] in
            let collected = Self.readDevices()
            DispatchQueue.main.async {
                guard let self else { return }
                self.devices = collected
                self.lastUpdated = Date()
                self.updateStatusItem()
            }
        }
    }

    /// Runs on a background queue: Receiver derives a run loop for whichever
    /// thread it is built on, so nothing here blocks the UI. Internal rather
    /// than private so `--check` can exercise this exact path.
    static func readDevices() -> [DeviceStatus] {
        for device in findReceivers() {
            guard let receiver = Receiver(device) else { continue }
            let slots = receiver.pairedDevices()
            guard !slots.isEmpty else { continue }
            return slots.map { slot in
                let model = Models.forName(slot.name)
                return DeviceStatus(
                    name: slot.name,
                    battery: model?.battery ?? "unknown battery",
                    reading: slot.reading,
                    estimate: slot.reading.map { Estimates.build(reading: $0, model: model) }
                        ?? Estimate())
            }
        }
        return []
    }

    // MARK: status item

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        guard !devices.isEmpty else {
            // The text fallback needs the image slot, otherwise `.imageOnly`
            // would hide it and leave an empty gap in the menu bar.
            button.imagePosition = .noImage
            button.image = nil
            button.title = "no receiver"
            button.toolTip = "No Logitech Unifying receiver found"
            return
        }
        button.imagePosition = .imageOnly
        button.title = ""
        button.image = statusImage(devices: devices, showIcons: showIcons)
        button.toolTip = devices.map { device -> String in
            guard let reading = device.reading else {
                return "\(device.name): asleep or switched off"
            }
            let range = reading.coarse
                ? "\(reading.socLow)\(Fmt.enDash)\(reading.socHigh)%"
                : "\(reading.reportedPercent)%"
            return "\(device.name): \(reading.band) \(range), \(reading.statusName)"
        }.joined(separator: "\n")
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: refreshInterval,
                                         repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Let the system slide the fire time so it can coalesce with other
        // wakeups. An exact repeating deadline is the one thing that makes a
        // background timer genuinely expensive, and there is nothing here that
        // needs one: the gauge is four steps wide and moves over weeks, so a
        // few minutes of slack is invisible. The dropdown also refreshes on
        // open when the data is more than 20s old, so what is on screen is
        // current regardless of when the timer last fired.
        timer.tolerance = max(1, refreshInterval * 0.1)
        refreshTimer = timer
    }

    @objc private func woke() {
        refresh()
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Opening the dropdown is a natural moment to make sure the data is not
        // stale - but not so eagerly that flipping it open twice in a row
        // re-reads the receiver.
        if lastUpdated.map({ Date().timeIntervalSince($0) > 20 }) ?? true {
            refresh()
        }
        menu.removeAllItems()
        guard !devices.isEmpty else {
            menu.addItem(withTitle: "No Logitech receiver found", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            addFooterItems(to: menu)
            return
        }

        for device in devices {
            let item = NSMenuItem()
            let block = DeviceBlockView(device: device)
            item.view = block
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh),
                                     keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let iconsItem = NSMenuItem(title: "Show Device Icons",
                                   action: #selector(toggleIcons), keyEquivalent: "")
        iconsItem.target = self
        iconsItem.state = showIcons ? .on : .off
        menu.addItem(iconsItem)

        let intervalMenu = NSMenu()
        for minutes in [1, 5, 15, 30] {
            let entry = NSMenuItem(title: "\(minutes) minute\(minutes == 1 ? "" : "s")",
                                   action: #selector(setInterval(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = minutes
            entry.state = Int(refreshInterval) == minutes * 60 ? .on : .off
            intervalMenu.addItem(entry)
        }
        let intervalItem = NSMenuItem(title: "Refresh Every", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        addFooterItems(to: menu)
    }

    private func addFooterItems(to menu: NSMenu) {
        let stamp = lastUpdated.map {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "Updated \(formatter.string(from: $0))"
        } ?? "Reading\u{2026}"
        let updated = NSMenuItem(title: stamp, action: nil, keyEquivalent: "")
        updated.isEnabled = false
        menu.addItem(updated)

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleIcons() {
        showIcons.toggle()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        refreshInterval = TimeInterval(sender.tag * 60)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change the login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
