//  HIDPP.swift
//  A minimal HID++ 2.0 client for Logitech Unifying receivers.
//
//  Swift port of the reader in ../mxbattery. The receiver exposes no "Battery"
//  HID element, so the level is only reachable by speaking HID++ 2.0 to the
//  receiver's *vendor* interface (usage page 0xFF00). See ../README.md for the
//  protocol notes; the three that bite hardest are repeated here:
//
//    * Error replies use a shifted layout: [0x8F][orig feat][orig fn<<4|sw]
//      [err][0], not the normal one.
//    * A short request can be answered by a long report, so never match on the
//      reply's report id.
//    * An empty slot and a sleeping device are indistinguishable by reply -
//      both answer instantly with HID++ error 0x09. Only the receiver's own
//      pairing register separates them.

import CoreFoundation
import Foundation
import IOKit
import IOKit.hid

enum HIDPP {
    static let logitechVendorID = 0x046D
    static let vendorUsagePage = 0xFF00
    static let vendorUsage = 0x01

    /// 4-bit tag echoed on replies. Deliberately distinct from the ids used by
    /// Logi Options+/G HUB (0x0D) and Solaar (0x0B) so replies cannot be
    /// confused if those are running.
    static let softwareID: UInt8 = 0x09

    static let reportIDShort: UInt8 = 0x10
    static let reportIDLong: UInt8 = 0x11
    static let errorMarker: UInt8 = 0x8F
    static let shortFrame = 7
    static let longFrame = 20

    static let featureBatteryStatus: UInt16 = 0x1000
    static let featureUnifiedBattery: UInt16 = 0x1004
    /// UNIFIED_BATTERY reports a power-of-two level, not a percentage.
    static let unifiedLevels: [UInt8: Int] = [8: 100, 4: 50, 2: 15, 1: 5]

    static let capabilityMileage: UInt8 = 1 << 1
    static let capabilityRechargeable: UInt8 = 1 << 2

    static let statusNames = ["discharging", "recharging", "almost full", "full",
                              "slow recharge", "invalid battery", "thermal error"]

    /// A busy device answers in a few ms; this only ever elapsed for a device
    /// that was not going to answer at all.
    static let replyTimeout: TimeInterval = 2.0

    /// A paired slot answers the name register in ~2 ms while an empty slot
    /// never answers, so this is ~30x margin without costing a quarter second
    /// per empty slot.
    static let pairingProbeTimeout: TimeInterval = 0.06
}

enum RequestOutcome {
    case reply([UInt8])
    case hidError(Int)
    case timeout
}

/// What one receiver slot gave us.
struct SlotResult {
    let slot: Int
    let name: String
    /// nil means the slot is paired but the device did not answer.
    let reading: BatteryReading?
}

struct BatteryReading {
    let reportedPercent: Int
    let statusName: String
    let rechargeable: Bool
    /// Fewer than 10 levels (or mileage off) means the firmware collapsed the
    /// gauge to 4 bands, so the reading is a range, not a measurement.
    let coarse: Bool
    let gaugeLevels: Int?
    let socLow: Int
    let socHigh: Int
    let band: String
}

// MARK: - Receiver enumeration

private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
}

/// Every Logitech HID++ interface on the system. A USB hub may host several
/// receivers, so this returns a list.
func findReceivers() -> [IOHIDDevice] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)  // enumerate all, filter below
    guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
    let count = CFSetGetCount(set)
    guard count > 0 else { return [] }
    var raw = [UnsafeRawPointer?](repeating: nil, count: count)
    CFSetGetValues(set, &raw)
    return raw.compactMap { pointer in
        guard let pointer else { return nil }
        let device = unsafeBitCast(pointer, to: IOHIDDevice.self)
        guard intProperty(device, "VendorID") == HIDPP.logitechVendorID,
              intProperty(device, "PrimaryUsagePage") == HIDPP.vendorUsagePage,
              intProperty(device, "PrimaryUsage") == HIDPP.vendorUsage
        else { return nil }
        return device
    }
}

// MARK: - Receiver

/// Input reports must stay valid for as long as the callback is registered, so
/// the handler is a C function pointer and the instance travels in `context`.
private let inputReportCallback: IOHIDReportCallback = { context, _, _, _, _, report, length in
    guard let context, length > 0 else { return }
    Unmanaged<Receiver>.fromOpaque(context).takeUnretainedValue()
        .enqueue(report, Int(length))
}

final class Receiver {
    private let device: IOHIDDevice
    private let verbose: Bool
    private var queue: [UInt8] = []
    private let buffer: UnsafeMutablePointer<UInt8>
    private let runLoopMode = CFRunLoopMode.defaultMode.rawValue

    init?(_ device: IOHIDDevice, verbose: Bool = false) {
        self.device = device
        self.verbose = verbose
        buffer = .allocate(capacity: 64)
        // Shared first: no TCC prompt and no root. Seizing is a fallback for
        // the rare case where something holds it exclusively.
        var opened = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            == kIOReturnSuccess
        if !opened {
            opened = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
                == kIOReturnSuccess
        }
        guard opened else {
            buffer.deallocate()
            return nil
        }
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), runLoopMode)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, inputReportCallback,
                                               Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), runLoopMode)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()
    }

    fileprivate func enqueue(_ report: UnsafeMutablePointer<UInt8>, _ length: Int) {
        queue.append(contentsOf: UnsafeBufferPointer(start: report, count: length))
    }

    private func trace(_ direction: String, _ frame: [UInt8]) {
        guard verbose else { return }
        FileHandle.standardError.write(
            Data(("   \(direction)  " + frame.map { String(format: "%02x", $0) }.joined(separator: " ")
                  + "\n").utf8))
    }

    private func send(_ frame: [UInt8]) {
        trace("TX", frame)
        frame.withUnsafeBufferPointer { body in
            _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput,
                                     CFIndex(frame[0]), body.baseAddress!, frame.count)
        }
    }

    /// Pop the first queued frame that `matches` accepts. Frames already
    /// skipped are discarded, exactly as the reference implementation does.
    private func wait(timeout: TimeInterval,
                      _ matches: ([UInt8]) -> Bool) -> [UInt8]? {
        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(timeout * 1_000_000_000)
        while true {
            var offset = 0
            while offset < queue.count {
                let length: Int
                switch queue[offset] {
                case HIDPP.reportIDShort: length = HIDPP.shortFrame
                case HIDPP.reportIDLong: length = HIDPP.longFrame
                default: length = 1
                }
                guard offset + length <= queue.count else { break }
                let frame = Array(queue[offset ..< offset + length])
                if matches(frame) {
                    queue.removeFirst(offset + length)
                    return frame
                }
                offset += length
            }
            if DispatchTime.now().uptimeNanoseconds >= deadline { return nil }
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.005, true)
        }
    }

    /// One HID++ request. `function` and `params` are packed into the header
    /// as [fn<<4 | softwareID] followed by the parameters.
    @discardableResult
    private func request(_ deviceIndex: UInt8, _ featureIndex: UInt8, _ function: UInt8,
                         _ params: [UInt8] = []) -> RequestOutcome {
        let isLong = params.count > 3
        var frame: [UInt8] = [isLong ? HIDPP.reportIDLong : HIDPP.reportIDShort,
                              deviceIndex, featureIndex,
                              (function << 4) | HIDPP.softwareID]
        frame += params
        frame += [UInt8](repeating: 0, count: (isLong ? HIDPP.longFrame : HIDPP.shortFrame)
                         - frame.count)
        let wanted = (function << 4) | HIDPP.softwareID
        send(frame)

        let reply = wait(timeout: HIDPP.replyTimeout) { candidate in
            guard candidate.count >= 4, candidate[1] == deviceIndex else { return false }
            if candidate[2] == HIDPP.errorMarker {
                return candidate.count >= 6
                    && candidate[3] == featureIndex && candidate[4] == wanted
            }
            return candidate[2] == featureIndex && candidate[3] == wanted
        }
        guard let reply else {
            trace("--", [])
            return .timeout
        }
        trace("RX", reply)
        if reply[2] == HIDPP.errorMarker {
            return .hidError(reply.count > 5 ? Int(reply[5]) : -1)
        }
        return .reply(Array(reply[4...]))
    }

    /// ROOT.GetFeature(feature id) -> index. 0 means unsupported, nil means the
    /// device never replied.
    private func featureIndex(_ deviceIndex: UInt8, _ feature: UInt16) -> UInt8? {
        switch request(deviceIndex, 0x00, 0x00,
                       [UInt8(feature >> 8), UInt8(feature & 0xFF)]) {
        case .timeout: return nil
        case .hidError: return 0
        case .reply(let params): return params.first ?? 0
        }
    }

    private func once(_ deviceIndex: UInt8) -> (reading: (Int, UInt8)?, timedOut: Bool) {
        var timedOut = false
        for (feature, function) in [(HIDPP.featureBatteryStatus, UInt8(0)),
                                    (HIDPP.featureUnifiedBattery, UInt8(1))] {
            guard let index = featureIndex(deviceIndex, feature) else {
                timedOut = true              // no reply at all: device asleep
                continue
            }
            if index == 0 { continue }       // HID++ error: feature not present
            switch request(deviceIndex, index, function) {
            case .timeout:
                timedOut = true
            case .hidError:
                continue
            case .reply(let params):
                guard !params.isEmpty else { continue }
                let percent = feature == HIDPP.featureUnifiedBattery
                    ? HIDPP.unifiedLevels[params.count > 1 ? params[1] : 8] ?? 5
                    : Int(params[0])
                return ((percent, params.count > 2 ? params[2] : 0), timedOut)
            }
        }
        return (nil, timedOut)
    }

    /// A device mid-wake can time out; an instant error is definitive.
    private func battery(_ deviceIndex: UInt8, attempts: Int = 3) -> (Int, UInt8)? {
        for _ in 0..<attempts {
            let (reading, timedOut) = once(deviceIndex)
            if !timedOut { return reading }
        }
        return nil
    }

    /// 0x1000 fn 1 GetBatteryCapability -> (levels, flags, critical%).
    private func capability(_ deviceIndex: UInt8) -> (levels: Int, flags: UInt8)? {
        guard let index = featureIndex(deviceIndex, HIDPP.featureBatteryStatus),
              index != 0 else { return nil }
        guard case .reply(let params) = request(deviceIndex, index, 0x01),
              params.count >= 2 else { return nil }
        return (Int(params[0]), params[1])
    }

    /// Paired devices are named in receiver register 0xB5, sub-register
    /// 0x40+slot. The name lives in the *receiver*, so it answers even while
    /// the device sleeps - which is the only way to tell a sleeping device
    /// from an empty slot.
    private func name(slot: Int, attempts: Int = 2,
                      timeout: TimeInterval = 0.4) -> String? {
        for _ in 0..<attempts {
            let frame: [UInt8] = [HIDPP.reportIDShort, 0xFF, 0x83, 0xB5,
                                  UInt8(0x40 + slot), 0x00, 0x00]
            send(frame)
            let reply = wait(timeout: timeout) { candidate in
                candidate.count >= HIDPP.longFrame && candidate[1] == 0xFF
                    && candidate[2] == 0x83 && candidate[3] == 0xB5
            }
            if let reply, reply.count > 6 {
                trace("RX", reply)
                let length = Int(reply[5])
                let bytes = reply[6 ..< min(6 + length, reply.count)]
                return String(decoding: bytes, as: UTF8.self)
            }
        }
        return nil
    }

    /// Every paired slot on this receiver, in slot order.
    func pairedDevices() -> [SlotResult] {
        var results: [SlotResult] = []
        for slot in 1...6 {
            guard let raw = battery(UInt8(slot)) else {
                // Nothing answered. The receiver still knows what is paired
                // here, which separates "asleep" from "empty slot".
                guard let paired = name(slot: slot - 1, attempts: 1,
                                        timeout: HIDPP.pairingProbeTimeout) else { continue }
                results.append(SlotResult(slot: slot, name: paired, reading: nil))
                continue
            }
            let (percent, status) = raw
            let label = name(slot: slot - 1, attempts: 1) ?? "device \(slot)"
            let caps = capability(UInt8(slot))
            let levels = caps?.levels
            let flags = caps?.flags ?? 0
            let coarse = levels == nil || levels! < 10
                || (flags & HIDPP.capabilityMileage) == 0
            let (low, high, band) = coarse
                ? bandFor(reported: percent)
                : (percent, percent, "")
            results.append(SlotResult(
                slot: slot, name: label,
                reading: BatteryReading(
                    reportedPercent: percent,
                    statusName: Int(status) < HIDPP.statusNames.count
                        ? HIDPP.statusNames[Int(status)] : "status \(status)",
                    rechargeable: (flags & HIDPP.capabilityRechargeable) != 0,
                    coarse: coarse,
                    gaugeLevels: levels,
                    socLow: low, socHigh: high, band: band)))
        }
        return results
    }
}

// MARK: - Gauge bands

/// HID++ 2.0, 0x1000 GetBatteryCapability: below 10 levels the firmware
/// collapses the gauge to 4 bands and sends that band's representative value,
/// so a reading is a range rather than a measurement.
let gaugeBands: [(low: Int, high: Int, label: String)] = [
    (81, 100, "full"), (31, 80, "good"), (11, 30, "low"), (0, 10, "critical"),
]

func bandFor(reported percent: Int) -> (Int, Int, String) {
    for band in gaugeBands where percent >= band.low {
        return (band.low, band.high, band.label)
    }
    return (0, 10, "critical")
}

func bandLabel(forSocLow percent: Int) -> String {
    bandFor(reported: percent).2
}
