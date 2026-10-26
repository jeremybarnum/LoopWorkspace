import Foundation
@testable import Trio

// Reference runner for checking a port of oref against Trio's Swift oref.
// Usage: oref-reference input.json output.json
// The input is {"cases": [...]}; the output is {"results": [...]} in the same order, one entry per case.
// A case that fails yields {"id": ..., "error": ...} and the batch goes on. Times are Unix milliseconds,
// glucose is mg/dL.

struct HarnessError: Error, CustomStringConvertible {
    let description: String
}

func number(_ value: Any?, _ name: String) throws -> Double {
    guard let n = value as? NSNumber else { throw HarnessError(description: "\(name) is missing or not a number") }
    return n.doubleValue
}

func optionalNumber(_ value: Any?) -> Double? {
    if value == nil || value is NSNull { return nil }
    return (value as? NSNumber)?.doubleValue
}

func rows(_ value: Any?, _ name: String, width: Int) throws -> [[Double]] {
    guard value == nil || value is NSNull || value is [Any] else { throw HarnessError(description: "\(name) is not a list") }
    guard let list = value as? [Any] else { return [] }
    return try list.enumerated().map { index, row in
        guard let row = row as? [Any], row.count == width else {
            throw HarnessError(description: "\(name)[\(index)] is not a list of \(width) numbers")
        }
        return try row.map { try number($0, "\(name)[\(index)]") }
    }
}

func date(ms: Double) -> Date {
    Date(timeIntervalSince1970: ms / 1000)
}

func makeInput(_ c: [String: Any]) throws -> OrefInput {
    let now = date(ms: try number(c["now_ms"], "now_ms"))
    guard let settings = c["settings"] as? [String: Any] else { throw HarnessError(description: "settings is missing") }

    var preferences = OrefPreferences()
    if let p = c["preferences"] as? [String: Any], !p.isEmpty {
        let data = try JSONSerialization.data(withJSONObject: p)
        preferences = try JSONDecoder().decode(OrefPreferences.self, from: data)
    }
    let diaHours = try number(settings["dia_hours"], "settings.dia_hours")
    preferences.insulinActionHours = diaHours

    let curve: OrefInput.InsulinCurve
    switch settings["curve"] as? String {
    case "ultra-rapid": curve = .ultraRapid
    case "rapid-acting": curve = .rapidActing
    default: throw HarnessError(description: "settings.curve must be \"ultra-rapid\" or \"rapid-acting\"")
    }

    let glucose = try rows(c["glucose"], "glucose", width: 2).map { OrefInput.Glucose(date: date(ms: $0[0]), mgdL: $0[1]) }
    let boluses = try rows(c["boluses"], "boluses", width: 2).enumerated().map { index, row in
        OrefInput.Dose.bolus(id: "b\(index)", date: date(ms: row[0]), units: row[1], automatic: false)
    }
    let temps = try rows(c["temp_basals"], "temp_basals", width: 3).enumerated().map { index, row in
        OrefInput.Dose.tempBasal(id: "t\(index)", start: date(ms: row[0]), minutes: row[1], unitsPerHour: row[2])
    }
    let carbs = try rows(c["carbs"], "carbs", width: 2).enumerated().map { index, row in
        OrefInput.Carbs(id: "c\(index)", date: date(ms: row[0]), grams: row[1])
    }

    var currentTemp: OrefInput.CurrentTemp?
    if let t = c["current_temp"] as? [String: Any] {
        currentTemp = OrefInput.CurrentTemp(
            start: date(ms: try number(t["start_ms"], "current_temp.start_ms")),
            minutesRemaining: try number(t["minutes_remaining"], "current_temp.minutes_remaining"),
            unitsPerHour: try number(t["units_per_hour"], "current_temp.units_per_hour")
        )
    }
    let tdd = c["tdd"] as? [String: Any]

    let rates = (settings["supported_basal_rates"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
    return OrefInput(
        now: now,
        glucose: glucose,
        doses: boluses + temps,
        carbs: carbs,
        basal: [OrefInput.ScheduleItem(minutes: 0, value: try number(settings["basal"], "settings.basal"))],
        sensitivity: [OrefInput.ScheduleItem(minutes: 0, value: try number(settings["isf"], "settings.isf"))],
        carbRatio: [OrefInput.ScheduleItem(minutes: 0, value: try number(settings["cr"], "settings.cr"))],
        targets: [OrefInput.TargetItem(
            minutes: 0,
            low: try number(settings["target_low"], "settings.target_low"),
            high: try number(settings["target_high"], "settings.target_high")
        )],
        suspendThreshold: try number(settings["suspend_threshold"], "settings.suspend_threshold"),
        maxBolus: try number(settings["max_bolus"], "settings.max_bolus"),
        maxBasalRate: try number(settings["max_basal"], "settings.max_basal"),
        insulinCurve: curve,
        insulinActionHours: diaHours,
        bolusIncrement: try number(settings["bolus_increment"], "settings.bolus_increment"),
        supportedBasalRates: rates,
        currentTemp: currentTemp,
        override: nil,
        reservoir: nil,
        totalDailyDose: optionalNumber(tdd?["total"]),
        averageDailyDose: optionalNumber(tdd?["average"]),
        preferences: preferences
    )
}

// JSON values: Decimals as numbers, nil as null.
func num(_ value: Decimal?) -> Any {
    guard let value, !value.isNaN else { return NSNull() }
    return NSDecimalNumber(decimal: value).doubleValue
}

func num(_ value: Double?) -> Any { value.map { $0 as Any } ?? NSNull() }
func num(_ value: Int?) -> Any { value.map { $0 as Any } ?? NSNull() }
func num(_ value: UInt64?) -> Any { value.map { $0 as Any } ?? NSNull() }
func ms(_ value: Date?) -> Any { value.map { ($0.timeIntervalSince1970 * 1000).rounded() as Any } ?? NSNull() }
func list(_ values: [Decimal]?) -> Any { values.map { $0.map { num($0) } as Any } ?? NSNull() }
func list(_ values: [Int]?) -> Any { values.map { $0 as Any } ?? NSNull() }

func encodeProfile(_ profile: Profile) throws -> Any {
    let data = try JSONCoding.encoder.encode(profile)
    return try JSONSerialization.jsonObject(with: data)
}

func encode(_ run: Oref.Run, id: Any) throws -> [String: Any] {
    let meal = run.meal
    let det = run.determination
    return [
        "id": id,
        "profile": try encodeProfile(run.profile),
        "autosens": [
            "ratio8h": num(run.autosens8h.ratio),
            "ratio24h": num(run.autosens24h.ratio),
            "ratio": num(run.autosens.ratio),
            "newisf": num(run.autosens.newisf),
        ],
        "glucose_status": (try? DeterminationGenerator.getGlucoseStatus(glucoseReadings: run.glucose))
            .flatMap { $0 }
            .map { gs -> Any in
                ["glucose": num(gs.glucose), "delta": num(gs.delta),
                 "short_avgdelta": num(gs.shortAvgDelta), "long_avgdelta": num(gs.longAvgDelta)]
            } ?? NSNull(),
        "meal": [
            "carbs": num(meal.carbs),
            "mealCOB": num(meal.mealCOB),
            "currentDeviation": num(meal.currentDeviation),
            "maxDeviation": num(meal.maxDeviation),
            "minDeviation": num(meal.minDeviation),
            "slopeFromMaxDeviation": num(meal.slopeFromMaxDeviation),
            "slopeFromMinDeviation": num(meal.slopeFromMinDeviation),
            "lastCarbTime": meal.lastCarbTime,
            "allDeviations": list(meal.allDeviations),
        ],
        "iob": run.iob.map { entry -> [String: Any] in
            [
                "iob": num(entry.iob),
                "activity": num(entry.activity),
                "basaliob": num(entry.basaliob),
                "bolusiob": num(entry.bolusiob),
                "netbasalinsulin": num(entry.netbasalinsulin),
                "bolusinsulin": num(entry.bolusinsulin),
                "time_ms": ms(entry.time),
                "zt_iob": num(entry.iobWithZeroTemp.iob),
                "zt_activity": num(entry.iobWithZeroTemp.activity),
            ]
        },
        "last_bolus_time_ms": num(run.iob.first?.lastBolusTime),
        "last_temp": run.iob.first?.lastTemp.map { temp -> [String: Any] in
            ["rate": num(temp.rate), "date_ms": num(temp.date), "duration": num(temp.duration)]
        } ?? NSNull(),
        "determination": [
            "rate": num(det.rate),
            "duration": num(det.duration),
            "units": num(det.units),
            "eventualBG": num(det.eventualBG),
            "bg": num(det.bg),
            "minPredBG": num(det.minPredBG),
            "minGuardBG": num(det.minGuardBG),
            "minDelta": num(det.minDelta),
            "expectedDelta": num(det.expectedDelta),
            "insulinReq": num(det.insulinReq),
            "sensitivityRatio": num(det.sensitivityRatio),
            "isf": num(det.isf),
            "carbRatio": num(det.carbRatio),
            "cob": num(det.cob),
            "iob": num(det.iob),
            "carbsReq": num(det.carbsReq),
            "threshold": num(det.threshold),
            "current_target": num(det.current_target),
            "tdd": num(det.tdd),
            "reservoir": num(det.reservoir),
            "temp": det.temp.map { $0.rawValue as Any } ?? NSNull(),
            "deliverAt_ms": ms(det.deliverAt),
            "timestamp_ms": ms(det.timestamp),
            "received": det.received.map { $0 as Any } ?? NSNull(),
            "reason": det.reason,
            "predBGs": [
                "IOB": list(det.predictions?.iob),
                "ZT": list(det.predictions?.zt),
                "COB": list(det.predictions?.cob),
                "UAM": list(det.predictions?.uam),
            ],
        ],
    ]
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: oref-reference input.json output.json\n".data(using: .utf8)!)
    exit(2)
}

do {
    let inputData = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    guard let top = try JSONSerialization.jsonObject(with: inputData) as? [String: Any],
          let cases = top["cases"] as? [[String: Any]]
    else { throw HarnessError(description: "input must be an object with a \"cases\" list") }

    var results: [[String: Any]] = []
    for c in cases {
        let id = c["id"] ?? NSNull()
        do {
            results.append(try encode(try Oref.run(try makeInput(c)), id: id))
        } catch {
            results.append(["id": id, "error": String(describing: error)])
        }
    }
    let outputData = try JSONSerialization.data(withJSONObject: ["results": results], options: [.sortedKeys])
    try outputData.write(to: URL(fileURLWithPath: arguments[2]))
} catch {
    FileHandle.standardError.write("oref-reference: \(error)\n".data(using: .utf8)!)
    exit(1)
}
