import XCTest
@testable import Trio

/// Checks the door into oref (Oref.swift) with simple situations whose direction is not in doubt.
/// oref's own arithmetic is Trio's and is tested in Trio.
final class OrefTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// 24 hours of readings every 5 minutes, ending now at `last` and moving `perReading` mg/dL per reading
    /// over the last hour; flat at `last - 12 * perReading` before that.
    func glucose(last: Double, perReading: Double) -> [OrefInput.Glucose] {
        (0 ..< 288).map { i in
            let steps = Double(min(i, 12))
            return OrefInput.Glucose(date: now.addingTimeInterval(TimeInterval(-300 * i)), mgdL: last - steps * perReading)
        }
    }

    func input(glucose: [OrefInput.Glucose], carbs: [OrefInput.Carbs] = [], doses: [OrefInput.Dose] = [],
               preferences: OrefPreferences = OrefPreferences()) -> OrefInput {
        OrefInput(
            now: now, glucose: glucose, doses: doses, carbs: carbs,
            basal: [.init(minutes: 0, value: 1.0)],
            sensitivity: [.init(minutes: 0, value: 50)],
            carbRatio: [.init(minutes: 0, value: 10)],
            targets: [.init(minutes: 0, low: 100, high: 100)],
            suspendThreshold: 70, maxBolus: 5, maxBasalRate: 4,
            insulinCurve: .rapidActing, insulinActionHours: 6, bolusIncrement: 0.05, supportedBasalRates: [],
            currentTemp: nil, override: nil, reservoir: 100,
            totalDailyDose: 30, averageDailyDose: 30, preferences: preferences
        )
    }

    var smbPreferences: OrefPreferences {
        var p = OrefPreferences()
        p.maxIOB = 5
        p.enableSMBAlways = true
        p.enableUAM = true
        return p
    }

    func testLowAndFallingGivesZeroTemp() throws {
        let output = try Oref.determine(input(glucose: glucose(last: 75, perReading: -3)))
        XCTAssertEqual(output.unitsPerHour, 0, output.reason)
        XCTAssertNil(output.microBolus, output.reason)
    }

    func testHighAndRisingWithMaxIOBZeroAddsNothing() throws {
        // Trio's default Max IOB of 0: no insulin above scheduled basal, however high.
        let output = try Oref.determine(input(glucose: glucose(last: 220, perReading: 4)))
        XCTAssertNil(output.microBolus, output.reason)
        XCTAssertLessThanOrEqual(output.unitsPerHour ?? 1.0, 1.0, output.reason)
    }

    func testHighAndRisingWithSMBGivesMicroBolus() throws {
        let output = try Oref.determine(input(glucose: glucose(last: 220, perReading: 4), preferences: smbPreferences))
        XCTAssertGreaterThan(output.microBolus ?? 0, 0, output.reason)
        XCTAssertLessThanOrEqual(output.microBolus ?? 0, 5)
    }

    func testRecentMicroBolusIsCounted() throws {
        // A 2 U automatic bolus 2 minutes ago: within the SMB interval, so no second one now.
        let dose = OrefInput.Dose.bolus(id: "b1", date: now.addingTimeInterval(-120), units: 2, automatic: true)
        let output = try Oref.determine(input(glucose: glucose(last: 220, perReading: 4), doses: [dose], preferences: smbPreferences))
        XCTAssertNil(output.microBolus, output.reason)
        XCTAssertGreaterThan(output.iob ?? 0, 1.5, output.reason)
    }

    func testCarbsOnBoardAreSeen() throws {
        let carbs = [OrefInput.Carbs(id: "c1", date: now.addingTimeInterval(-1800), grams: 40)]
        let output = try Oref.determine(input(glucose: glucose(last: 140, perReading: 2), carbs: carbs, preferences: smbPreferences))
        XCTAssertGreaterThan(output.cob ?? 0, 0, output.reason)
    }

    func testPumpHistoryIsNewestFirstWithDurationBeforeRate() {
        let events = Oref.pumpHistoryEvents([
            .tempBasal(id: "t1", start: now.addingTimeInterval(-3600), minutes: 30, unitsPerHour: 2),
            .bolus(id: "b1", date: now.addingTimeInterval(-600), units: 1, automatic: false),
            .suspend(id: "s1", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-6600))
        ], now: now)
        XCTAssertEqual(events.map(\.type), [.bolus, .tempBasalDuration, .tempBasal, .pumpResume, .pumpSuspend])
    }

    func testStoredPreferencesSurviveMissingFields() throws {
        let decoded = try JSONDecoder().decode(OrefPreferences.self, from: Data(#"{"maxIOB": 3}"#.utf8))
        XCTAssertEqual(decoded.maxIOB, 3)
        XCTAssertEqual(decoded.autosensMax, OrefPreferences().autosensMax)
        XCTAssertEqual(decoded.insulinActionHours, 10, "Trio's default insulin duration")
    }

    func testLongerInsulinDurationCountsMoreInsulinActive() throws {
        let dose = OrefInput.Dose.bolus(id: "b1", date: now.addingTimeInterval(-3 * 3600), units: 4, automatic: false)
        var six = input(glucose: glucose(last: 120, perReading: 0), doses: [dose]); six.insulinActionHours = 6
        var ten = six; ten.insulinActionHours = 10
        let iob6 = try XCTUnwrap(Oref.determine(six).iob), iob10 = try XCTUnwrap(Oref.determine(ten).iob)
        XCTAssertGreaterThan(iob10, iob6, "a 10 h tail leaves more of a 3 h old bolus active")
    }
}
