//  Model.swift
//  Per-device battery models and the runtime estimates built from them.
//
//  Every figure here is CALENDAR time with the device powered on, not "days of
//  actual use": a paired device keeps drawing current while idle (radio link
//  upkeep, periodic wake-ups), so wall-clock time is what drains it.
//  `selfMicroAmps` is the chemistry's own self-discharge, which runs even when
//  the device is switched off. Sources are in ../README.md.

import Foundation

struct DeviceModel {
    /// Substring of the device name that selects this model.
    let match: String
    let battery: String
    /// Nameplate capacity in mAh.
    let capacity: Double
    /// Self-discharge in microamps averaged. Li-Po also carries its protection
    /// circuit; alkaline is ~20x lower.
    let selfMicroAmps: Double
    /// Draw while actually moving or typing. Fitted to owner reports, not
    /// measured; nil means it cannot be derived at all.
    let activeMicroAmps: Double?
    /// (label, days per charge low, days per charge high) from owner reports
    /// and manufacturer ratings.
    let scenarios: [(label: String, low: Double, high: Double)]
}

enum Models {
    /// Alkaline cells are rated ~10 years shelf life and can leak, so cap the
    /// "switched off" figure instead of trusting the arithmetic.
    static let shelfCapMonths = 120.0

    static let all: [DeviceModel] = [
        DeviceModel(match: "MX ERGO", battery: "500 mAh Li-Po",
                    capacity: 500, selfMicroAmps: 30, activeMicroAmps: 500,
                    scenarios: [("powered on, daily use", 47, 63),
                                ("powered on, light use", 90, 120)]),
        DeviceModel(match: "ERGO K860", battery: "2x AAA alkaline",
                    capacity: 1100, selfMicroAmps: 3.5, activeMicroAmps: nil,
                    scenarios: [("powered on, typical use", 365, 730)]),
    ]

    static func forName(_ name: String) -> DeviceModel? {
        let upper = name.uppercased()
        return all.first { upper.contains($0.match) }
    }
}

/// Everything the UI can show beyond the raw reading. Absent fields mean the
/// quantity could not be derived for this device.
struct Estimate {
    var scenarios: [(label: String, low: Double, high: Double)] = []
    var monthsOff: Double?
    var selfPercentPerMonth: Double?
    var selfShareLow: Double?
    var selfShareHigh: Double?
    var activeHoursLow: Int?
    var activeHoursHigh: Int?
}

enum Estimates {
    /// Self-discharge expressed as a share of one full charge, over `days` of
    /// calendar time.
    static func selfShare(selfMicroAmps: Double, capacity: Double, days: Double) -> Double {
        selfMicroAmps * days * 24 / 1000 / capacity * 100
    }

    static func percentPerMonth(selfMicroAmps: Double, capacity: Double) -> Double {
        selfMicroAmps * 0.7305 / capacity * 100
    }

    static func shelfMonths(capacity: Double, selfMicroAmps: Double) -> Double {
        min(Models.shelfCapMonths, capacity / (selfMicroAmps * 0.7305))
    }

    static func build(reading: BatteryReading, model: DeviceModel?) -> Estimate {
        var estimate = Estimate()
        guard let model, !model.scenarios.isEmpty else { return estimate }

        // A coarse reading is a band, so every scenario scales into the band's
        // floor and ceiling rather than being treated as a point value.
        let low = Double(reading.socLow)
        let high = Double(reading.socHigh)
        estimate.scenarios = model.scenarios.map {
            ($0.label, $0.low * low / 100, $0.high * high / 100)
        }

        if model.capacity > 0, model.selfMicroAmps > 0 {
            estimate.monthsOff = shelfMonths(capacity: model.capacity,
                                             selfMicroAmps: model.selfMicroAmps)
            estimate.selfPercentPerMonth = percentPerMonth(selfMicroAmps: model.selfMicroAmps,
                                                           capacity: model.capacity)
            let shortest = estimate.scenarios.map(\.low).min() ?? 0
            let longest = estimate.scenarios.map(\.high).max() ?? 0
            estimate.selfShareLow = selfShare(selfMicroAmps: model.selfMicroAmps,
                                              capacity: model.capacity, days: shortest)
            estimate.selfShareHigh = selfShare(selfMicroAmps: model.selfMicroAmps,
                                               capacity: model.capacity, days: longest)
        }

        if model.capacity > 0, let active = model.activeMicroAmps {
            estimate.activeHoursLow =
                Int((model.capacity * 1000 * low / 100 / active).rounded())
            estimate.activeHoursHigh =
                Int((model.capacity * 1000 * high / 100 / active).rounded())
        }
        return estimate
    }
}

/// Formatters shared by the menu bar and the CLI probe, matching ../mxbattery.
enum Fmt {
    static let enDash = "\u{2013}"

    /// Human units: months once the estimate reaches roughly a year.
    static func range(daysLow: Double, daysHigh: Double) -> String {
        let unit: String
        let scale: Double
        if daysHigh >= 330 {
            unit = "months"; scale = 30.44
        } else if daysHigh >= 2 {
            unit = "days"; scale = 1
        } else {
            unit = "hours"; scale = 1.0 / 24
        }
        let low = String(format: "%.0f", daysLow / scale)
        let high = String(format: "%.0f", daysHigh / scale)
        return low == high ? "\(high) \(unit)" : "\(low)\(enDash)\(high) \(unit)"
    }

    /// A single duration in months, switching to years once it is long.
    static func months(_ value: Double) -> String {
        value >= 24
            ? "\(String(format: "%.0f", value / 12)) years"
            : "\(String(format: "%.0f", value)) months"
    }

    /// "a-b unit", or just "a unit" when both ends agree.
    static func pair(low: Int, high: Int, unit: String) -> String {
        low == high ? "\(high) \(unit)" : "\(low)\(enDash)\(high) \(unit)"
    }

    /// Decimal rounding for machine output, matching Python's `round(x, n)`.
    /// printf rounds the exact binary value correctly, whereas
    /// `(x * 10).rounded() / 10` rounds half *away from zero* once the
    /// multiplication itself rounds up to an exact tie - which is how 295.65
    /// became 295.7 instead of 295.6.
    static func round1(_ value: Double) -> Double {
        Double(String(format: "%.1f", value)) ?? value
    }

    static func round2(_ value: Double) -> Double {
        Double(String(format: "%.2f", value)) ?? value
    }
}
