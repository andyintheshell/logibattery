//  probe/main.swift
//  Diagnostic CLI: dumps everything the Swift port sees, using the same JSON
//  schema as `../mxbattery --json`, so the two can be diffed field-by-field.
//  Build with build.sh; this is a development aid, not part of the app.
//
//  -v     trace raw HID++ frames
//  --bg   perform the read on a background dispatch queue, exactly as the app
//         does, to prove the IOKit callback run loop works off the main thread

import CoreFoundation
import Foundation

let verbose = CommandLine.arguments.contains("-v")
let useBackgroundQueue = CommandLine.arguments.contains("--bg")

/// Everything below `collectSlots` is thread-agnostic; the Receiver derives a
/// run loop for whichever thread it is constructed on.
func collectSlots() -> (rows: [[String: Any]], readSomething: Bool) {
    var rows: [[String: Any]] = []
    var readSomething = false

    for device in findReceivers() {
        guard let receiver = Receiver(device, verbose: verbose) else { continue }
        for result in receiver.pairedDevices() {
            let model = Models.forName(result.name)
            var row: [String: Any] = [
                "name": result.name,
                "slot": result.slot,
                "battery": (model?.battery) ?? "unknown battery",
            ]
            guard let reading = result.reading else {
                row["asleep"] = true
                rows.append(row)
                continue
            }
            readSomething = true
            row["reported_percent"] = reading.reportedPercent
            row["status"] = reading.statusName
            row["gauge_levels"] = reading.gaugeLevels ?? NSNull()
            row["rechargeable"] = reading.rechargeable
            row["coarse"] = reading.coarse
            row["band"] = reading.band
            row["soc_low"] = reading.socLow
            row["soc_high"] = reading.socHigh

            let estimate = Estimates.build(reading: reading, model: model)
            row["scenarios"] = estimate.scenarios.map {
                ["label": $0.label,
                 "days_low": Fmt.round1($0.low),
                 "days_high": Fmt.round1($0.high)]
            }
            if let value = estimate.monthsOff { row["months_off"] = Fmt.round1(value) }
            if let value = estimate.selfPercentPerMonth {
                row["self_pct_per_month"] = Fmt.round2(value)
            }
            if let value = estimate.selfShareLow { row["self_share_low"] = Fmt.round1(value) }
            if let value = estimate.selfShareHigh { row["self_share_high"] = Fmt.round1(value) }
            if let value = estimate.activeHoursLow { row["active_hours_low"] = value }
            if let value = estimate.activeHoursHigh { row["active_hours_high"] = value }
            rows.append(row)
        }
        if !rows.isEmpty { break }
    }
    return (rows, readSomething)
}

guard !findReceivers().isEmpty else {
    FileHandle.standardError.write(Data("no Logitech HID++ receiver found\n".utf8))
    exit(1)
}

var result = (rows: [[String: Any]](), readSomething: false)
if useBackgroundQueue {
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
        result = collectSlots()
        done.signal()
    }
    done.wait()
} else {
    result = collectSlots()
}

let data = try JSONSerialization.data(withJSONObject: result.rows,
                                      options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
exit(result.readSomething ? 0 : 1)
