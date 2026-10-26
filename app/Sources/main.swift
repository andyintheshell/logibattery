//  main.swift
//  LogiBattery - a menu bar readout for Logitech devices paired through a
//  Unifying receiver.
//
//  `--dump-png <dir>` renders the menu bar image and the dropdown blocks
//  offscreen to PNG files. That exists so the drawing can be checked (and
//  diffed) without a pair of eyes on the menu bar, and so both appearances can
//  be verified on demand.

import AppKit

// MARK: - Offscreen rendering, for verification

private func pngData(of image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

private func pngData(of view: NSView) -> Data? {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.representation(using: .png, properties: [:])
}

/// Blow a tiny menu bar image up so it can actually be inspected.
private func scaled(_ image: NSImage, by scale: CGFloat, background: NSColor) -> NSImage {
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let out = NSImage(size: size)
    out.lockFocus()
    background.setFill()
    NSRect(origin: .zero, size: size).fill()
    NSGraphicsContext.current?.imageInterpolation = .none
    image.draw(in: NSRect(origin: .zero, size: size))
    out.unlockFocus()
    return out
}

private func syntheticDevice(_ model: String?, name: String, battery: String,
                             low: Int, high: Int, reported: Int,
                             band: String, status: String = "discharging") -> DeviceStatus {
    let reading = BatteryReading(reportedPercent: reported, statusName: status,
                                 rechargeable: model == "MX ERGO", coarse: true,
                                 gaugeLevels: 4, socLow: low, socHigh: high, band: band)
    let found = model.flatMap { Models.forName($0) }
    return DeviceStatus(name: name, battery: battery, reading: reading,
                        estimate: Estimates.build(reading: reading, model: found))
}

private func asleepDevice(name: String, battery: String, model: String?) -> DeviceStatus {
    DeviceStatus(name: name, battery: battery, reading: nil,
                 estimate: Estimates.build(
                    reading: BatteryReading(reportedPercent: 0, statusName: "discharging",
                                            rechargeable: false, coarse: true, gaugeLevels: nil,
                                            socLow: 0, socHigh: 0, band: ""),
                    model: model.flatMap { Models.forName($0) }))
}

private func write(_ data: Data?, _ name: String, _ directory: URL, note: String = "") {
    guard let data else { print("  failed to render \(name)"); return }
    try? data.write(to: directory.appendingPathComponent(name))
    print("  \(name)\(note.isEmpty ? "" : "  \(note)")")
}

private func dumpPNGs(to directory: URL) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    // One device per band the gauge can report, a keyboard, and a device that
    // did not answer.
    func mouse(_ low: Int, _ high: Int, _ reported: Int, _ band: String) -> DeviceStatus {
        syntheticDevice("MX ERGO", name: "MX Ergo", battery: "500 mAh Li-Po",
                        low: low, high: high, reported: reported, band: band)
    }
    let mouseFull = mouse(81, 100, 90, "full")
    let mouseGood = mouse(31, 80, 50, "good")
    let mouseLow = mouse(11, 30, 20, "low")
    let mouseCritical = mouse(0, 10, 5, "critical")
    let keyboard = syntheticDevice("ERGO K860", name: "ERGO K860",
                                   battery: "2x AAA alkaline",
                                   low: 81, high: 100, reported: 100, band: "full")
    let keyboardAsleep = asleepDevice(name: "ERGO K860", battery: "2x AAA alkaline",
                                      model: "ERGO K860")
    let samples = [mouseFull, mouseGood, mouseLow, mouseCritical, keyboard, keyboardAsleep]

    for (appearanceName, menuBar) in [
        ("light", NSColor(calibratedWhite: 0.93, alpha: 1)),
        ("dark", NSColor(calibratedWhite: 0.22, alpha: 1)),
    ] {
        let appearance = NSAppearance(named: appearanceName == "light" ? .aqua : .darkAqua)!
        appearance.performAsCurrentDrawingAppearance {
            // Menu bar strip: a typical pair, the alarming end, a sleeping
            // device, and the icon-free variant.
            for (label, devices, icons) in [
                ("typical", [keyboard, mouseGood], true),
                ("low+critical", [mouseLow, mouseCritical], true),
                ("asleep", [mouseGood, keyboardAsleep], true),
                ("bars-only", [keyboard, mouseGood], false),
                ("empty", [], true),
            ] {
                let image = statusImage(devices: devices, showIcons: icons)
                // Printing the layout size keeps a clipped or over-wide menu bar
                // image visible in the build output instead of silent.
                write(pngData(of: scaled(image, by: 6, background: menuBar)),
                      "status-\(appearanceName)-\(label).png", directory,
                      note: "\(Int(image.size.width))x\(Int(image.size.height)) pt"
                            + (icons ? "" : "  (bars only)"))
            }

            // Dropdown: each block on its own, then all of them stacked.
            for (index, device) in samples.enumerated() {
                let view = DeviceBlockView(device: device)
                view.appearance = appearance
                if let data = pngData(of: view) {
                    try? data.write(to: directory
                        .appendingPathComponent("block-\(appearanceName)-\(index).png"))
                }
            }
            let blocks = samples.map { DeviceBlockView(device: $0) }
            let stack = NSView(frame: NSRect(x: 0, y: 0, width: DeviceBlockView.blockWidth,
                                             height: blocks.reduce(0) { $0 + $1.frame.height }))
            stack.appearance = appearance
            var y = stack.frame.height
            for block in blocks {
                y -= block.frame.height
                block.setFrameOrigin(NSPoint(x: 0, y: y))
                stack.addSubview(block)
            }
            write(pngData(of: stack), "menu-\(appearanceName).png", directory)
        }
    }
    print("  (dropdown blocks stacked in menu-*.png)")
}

// MARK: - Entry point

if let flag = CommandLine.arguments.firstIndex(of: "--dump-png") {
    let path = CommandLine.arguments.count > flag + 1
        ? CommandLine.arguments[flag + 1] : "/tmp/logibattery-ui"
    print("rendering UI samples to \(path):")
    dumpPNGs(to: URL(fileURLWithPath: path))
    exit(0)
}

/// One live read through the very code path the status item uses, printed to
/// stdout. Lets the app's reading be verified without eyes on the menu bar.
if CommandLine.arguments.contains("--check") {
    var devices: [DeviceStatus] = []
    let finished = DispatchSemaphore(value: 0)
    DispatchQueue(label: "logibattery.check", qos: .userInitiated).async {
        devices = MenuBarController.readDevices()
        finished.signal()
    }
    finished.wait()

    print("devices found: \(devices.count)")
    for device in devices {
        guard let reading = device.reading else {
            print("  \(device.name)  asleep or switched off  [\(device.battery)]")
            continue
        }
        let range = reading.coarse
            ? "\(reading.socLow)\(Fmt.enDash)\(reading.socHigh)%"
            : "\(reading.reportedPercent)%"
        print("  \(device.name)  \(reading.band) \(range)  \(reading.statusName)"
              + "  [\(device.battery)]")
        for scenario in device.estimate.scenarios {
            print("      \(scenario.label): "
                  + Fmt.range(daysLow: scenario.low, daysHigh: scenario.high))
        }
        if let months = device.estimate.monthsOff {
            print("      switched off: \(Fmt.months(months))")
        }
    }

    // Optionally render the live menu bar image, so what the status item will
    // actually show can be inspected without a display.
    if let flag = CommandLine.arguments.firstIndex(of: "--png"),
       CommandLine.arguments.count > flag + 1 {
        let path = CommandLine.arguments[flag + 1]
        if let data = devices.isEmpty ? nil : pngData(of: scaled(
            statusImage(devices: devices, showIcons: true), by: 6,
            background: NSColor(calibratedWhite: 0.93, alpha: 1))) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("  live menu bar image: \(path)")
        }
    }
    exit(devices.isEmpty ? 1 : 0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuBarController()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
application.run()
