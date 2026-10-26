import Foundation

// The one door between Loop and Trio's oref. Plain values in, plain values out; everything inside
// the Trio folder is Trio's code, unmodified. All glucose values are mg/dL.

/// Which algorithm doses. `orefShadow` doses with Loop and runs oref beside it, logging what oref would do.
public enum DosingAlgorithm: String, Codable, CaseIterable, Sendable {
    case loop
    case orefShadow
    case oref
}

/// The oref settings Loop stores: the ones Trio's settings screens show, at Trio's defaults.
/// Settings Loop already has (targets, ISF, carb ratios, basal, max basal, max bolus, suspend threshold,
/// insulin type) are taken from Loop and are not repeated here. Insulin duration is oref's own: Trio's
/// 10 hours is not Loop's 6 (oref's curve keeps the peak fixed and only lengthens the tail).
public struct OrefPreferences: Codable, Equatable, Sendable {
    // Limits
    public var maxIOB: Double = 0
    public var maxCOB: Double = 120
    public var maxDailySafetyMultiplier: Double = 3
    public var currentBasalSafetyMultiplier: Double = 4
    // Insulin: how long insulin acts. Trio's default and recommendation is 10 hours (range 5–10);
    // the curve's peak follows the pump's insulin type (rapid-acting or ultra-rapid).
    public var insulinActionHours: Double = 10
    // Autosens
    public var autosensMax: Double = 1.2
    public var autosensMin: Double = 0.7
    // Super micro boluses (SMB) and unannounced meals (UAM)
    public var enableSMBAlways: Bool = false
    public var enableSMBWithCOB: Bool = false
    public var enableSMBWithTemptarget: Bool = false
    public var enableSMBAfterCarbs: Bool = false
    public var enableSMBHighBG: Bool = false
    public var enableSMBHighBGTarget: Double = 110
    public var allowSMBWithHighTemptarget: Bool = false
    public var maxSMBBasalMinutes: Double = 30
    public var enableUAM: Bool = false
    public var maxUAMSMBBasalMinutes: Double = 30
    public var smbInterval: Double = 3
    public var smbDeliveryRatio: Double = 0.5
    public var maxDeltaBGThreshold: Double = 0.2
    // Meals
    public var maxMealAbsorptionTime: Double = 6
    public var min5mCarbImpact: Double = 8
    public var remainingCarbsFraction: Double = 1.0
    public var remainingCarbsCap: Double = 90
    // Dynamic ISF
    public var useNewFormula: Bool = false
    public var sigmoid: Bool = false
    public var adjustmentFactor: Double = 0.8
    public var adjustmentFactorSigmoid: Double = 0.5
    public var weightPercentage: Double = 0.35
    public var tddAdjBasal: Bool = false
    // Target behaviour
    public var highTemptargetRaisesSensitivity: Bool = false
    public var lowTemptargetLowersSensitivity: Bool = false
    public var sensitivityRaisesTarget: Bool = false
    public var resistanceLowersTarget: Bool = false
    public var halfBasalExerciseTarget: Double = 160

    public init() {}

    // Decode field by field so a stored value survives fields added later.
    public init(from decoder: Decoder) throws {
        let defaults = OrefPreferences()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        maxIOB = v(.maxIOB, defaults.maxIOB)
        maxCOB = v(.maxCOB, defaults.maxCOB)
        maxDailySafetyMultiplier = v(.maxDailySafetyMultiplier, defaults.maxDailySafetyMultiplier)
        currentBasalSafetyMultiplier = v(.currentBasalSafetyMultiplier, defaults.currentBasalSafetyMultiplier)
        insulinActionHours = v(.insulinActionHours, defaults.insulinActionHours)
        autosensMax = v(.autosensMax, defaults.autosensMax)
        autosensMin = v(.autosensMin, defaults.autosensMin)
        enableSMBAlways = v(.enableSMBAlways, defaults.enableSMBAlways)
        enableSMBWithCOB = v(.enableSMBWithCOB, defaults.enableSMBWithCOB)
        enableSMBWithTemptarget = v(.enableSMBWithTemptarget, defaults.enableSMBWithTemptarget)
        enableSMBAfterCarbs = v(.enableSMBAfterCarbs, defaults.enableSMBAfterCarbs)
        enableSMBHighBG = v(.enableSMBHighBG, defaults.enableSMBHighBG)
        enableSMBHighBGTarget = v(.enableSMBHighBGTarget, defaults.enableSMBHighBGTarget)
        allowSMBWithHighTemptarget = v(.allowSMBWithHighTemptarget, defaults.allowSMBWithHighTemptarget)
        maxSMBBasalMinutes = v(.maxSMBBasalMinutes, defaults.maxSMBBasalMinutes)
        enableUAM = v(.enableUAM, defaults.enableUAM)
        maxUAMSMBBasalMinutes = v(.maxUAMSMBBasalMinutes, defaults.maxUAMSMBBasalMinutes)
        smbInterval = v(.smbInterval, defaults.smbInterval)
        smbDeliveryRatio = v(.smbDeliveryRatio, defaults.smbDeliveryRatio)
        maxDeltaBGThreshold = v(.maxDeltaBGThreshold, defaults.maxDeltaBGThreshold)
        maxMealAbsorptionTime = v(.maxMealAbsorptionTime, defaults.maxMealAbsorptionTime)
        min5mCarbImpact = v(.min5mCarbImpact, defaults.min5mCarbImpact)
        remainingCarbsFraction = v(.remainingCarbsFraction, defaults.remainingCarbsFraction)
        remainingCarbsCap = v(.remainingCarbsCap, defaults.remainingCarbsCap)
        useNewFormula = v(.useNewFormula, defaults.useNewFormula)
        sigmoid = v(.sigmoid, defaults.sigmoid)
        adjustmentFactor = v(.adjustmentFactor, defaults.adjustmentFactor)
        adjustmentFactorSigmoid = v(.adjustmentFactorSigmoid, defaults.adjustmentFactorSigmoid)
        weightPercentage = v(.weightPercentage, defaults.weightPercentage)
        tddAdjBasal = v(.tddAdjBasal, defaults.tddAdjBasal)
        highTemptargetRaisesSensitivity = v(.highTemptargetRaisesSensitivity, defaults.highTemptargetRaisesSensitivity)
        lowTemptargetLowersSensitivity = v(.lowTemptargetLowersSensitivity, defaults.lowTemptargetLowersSensitivity)
        sensitivityRaisesTarget = v(.sensitivityRaisesTarget, defaults.sensitivityRaisesTarget)
        resistanceLowersTarget = v(.resistanceLowersTarget, defaults.resistanceLowersTarget)
        halfBasalExerciseTarget = v(.halfBasalExerciseTarget, defaults.halfBasalExerciseTarget)
    }
}

/// What Loop stores: the algorithm choice and oref's own settings.
public struct OrefConfiguration: Codable, Equatable, Sendable {
    public var algorithm: DosingAlgorithm = .loop
    public var preferences = OrefPreferences()

    public init() {}

    static let defaultsKey = "com.loopkit.Loop.OrefConfiguration"

    public static func load(from defaults: UserDefaults) -> OrefConfiguration {
        guard let data = defaults.data(forKey: defaultsKey),
              let configuration = try? JSONDecoder().decode(OrefConfiguration.self, from: data)
        else { return OrefConfiguration() }
        return configuration
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

public struct OrefInput: Sendable {
    public struct Glucose: Sendable {
        public var date: Date
        public var mgdL: Double
        public init(date: Date, mgdL: Double) { self.date = date; self.mgdL = mgdL }
    }

    public enum Dose: Sendable {
        case bolus(id: String, date: Date, units: Double, automatic: Bool)
        case tempBasal(id: String, start: Date, minutes: Double, unitsPerHour: Double)
        case suspend(id: String, start: Date, end: Date?)
    }

    public struct Carbs: Sendable {
        public var id: String
        public var date: Date
        public var grams: Double
        public init(id: String, date: Date, grams: Double) { self.id = id; self.date = date; self.grams = grams }
    }

    /// One entry of a daily schedule, in minutes after local midnight (device time zone).
    public struct ScheduleItem: Sendable {
        public var minutes: Int
        public var value: Double
        public init(minutes: Int, value: Double) { self.minutes = minutes; self.value = value }
    }

    public struct TargetItem: Sendable {
        public var minutes: Int
        public var low: Double
        public var high: Double
        public init(minutes: Int, low: Double, high: Double) { self.minutes = minutes; self.low = low; self.high = high }
    }

    /// Loop's active override or pre-meal preset, in oref's terms.
    public struct Override: Sendable {
        /// Insulin needs as a percentage (Loop's scale factor × 100); applied to basal, ISF and carb ratio.
        public var percentage: Double
        /// The override's target in mg/dL, or nil to keep the scheduled target.
        public var target: Double?
        public init(percentage: Double, target: Double?) { self.percentage = percentage; self.target = target }
    }

    public struct CurrentTemp: Sendable {
        public var start: Date
        public var minutesRemaining: Double
        public var unitsPerHour: Double
        public init(start: Date, minutesRemaining: Double, unitsPerHour: Double) {
            self.start = start; self.minutesRemaining = minutesRemaining; self.unitsPerHour = unitsPerHour
        }
    }

    public enum InsulinCurve: Sendable {
        case rapidActing
        case ultraRapid
    }

    public var now: Date
    /// Ideally 24 hours, for autosens.
    public var glucose: [Glucose]
    /// Ideally 24 hours plus the insulin action time, for autosens and IOB.
    public var doses: [Dose]
    public var carbs: [Carbs]
    public var basal: [ScheduleItem]
    public var sensitivity: [ScheduleItem]
    public var carbRatio: [ScheduleItem]
    public var targets: [TargetItem]
    /// Loop's suspend threshold, used as oref's minimum safety threshold.
    public var suspendThreshold: Double
    public var maxBolus: Double
    public var maxBasalRate: Double
    public var insulinCurve: InsulinCurve
    /// From `preferences.insulinActionHours` unless set otherwise; at least 5 (oref's minimum).
    public var insulinActionHours: Double
    public var bolusIncrement: Double
    public var supportedBasalRates: [Double]
    public var currentTemp: CurrentTemp?
    public var override: Override?
    public var reservoir: Double?
    /// Insulin delivered over the last 24 hours, and the average per day over the days available.
    public var totalDailyDose: Double?
    public var averageDailyDose: Double?
    public var preferences: OrefPreferences

    public init(
        now: Date, glucose: [Glucose], doses: [Dose], carbs: [Carbs],
        basal: [ScheduleItem], sensitivity: [ScheduleItem], carbRatio: [ScheduleItem], targets: [TargetItem],
        suspendThreshold: Double, maxBolus: Double, maxBasalRate: Double,
        insulinCurve: InsulinCurve, insulinActionHours: Double, bolusIncrement: Double, supportedBasalRates: [Double],
        currentTemp: CurrentTemp?, override: Override?, reservoir: Double?,
        totalDailyDose: Double?, averageDailyDose: Double?, preferences: OrefPreferences
    ) {
        self.now = now; self.glucose = glucose; self.doses = doses; self.carbs = carbs
        self.basal = basal; self.sensitivity = sensitivity; self.carbRatio = carbRatio; self.targets = targets
        self.suspendThreshold = suspendThreshold; self.maxBolus = maxBolus; self.maxBasalRate = maxBasalRate
        self.insulinCurve = insulinCurve; self.insulinActionHours = insulinActionHours
        self.bolusIncrement = bolusIncrement; self.supportedBasalRates = supportedBasalRates
        self.currentTemp = currentTemp; self.override = override; self.reservoir = reservoir
        self.totalDailyDose = totalDailyDose; self.averageDailyDose = averageDailyDose; self.preferences = preferences
    }
}

public struct OrefOutput: Sendable {
    public struct Forecasts: Sendable {
        public var iob: [Int]
        public var cob: [Int]
        public var uam: [Int]
        public var zeroTemp: [Int]
    }

    public var date: Date
    /// The temp basal oref asks for; nil means keep what is running.
    public var unitsPerHour: Double?
    public var durationMinutes: Double?
    /// A super micro bolus, if any.
    public var microBolus: Double?
    public var reason: String
    public var eventualBG: Double?
    public var minPredBG: Double?
    public var minGuardBG: Double?
    public var insulinReq: Double?
    public var sensitivityRatio: Double?
    public var iob: Double?
    public var cob: Double?
    public var isf: Double?
    public var target: Double?
    public var forecasts: Forecasts
    /// Set when oref ran with dynamic ISF switched off for want of daily insulin history.
    public var dynamicISFSkipped: Bool
}

public enum OrefError: Error, CustomStringConvertible {
    case noDetermination
    case notEnoughData(String)

    public var description: String {
        switch self {
        case .noDetermination: return "oref returned no determination"
        case let .notEnoughData(what): return "oref: not enough data (\(what))"
        }
    }
}

public enum Oref {
    /// Everything one cycle computes on the way to its determination, for tests and reference runs.
    struct Run {
        var profile: Profile
        var preferences: Preferences
        var pumpHistory: [PumpHistoryEvent]
        var glucose: [BloodGlucose]
        var carbs: [CarbsEntry]
        var autosens8h: Autosens
        var autosens24h: Autosens
        var autosens: Autosens
        var meal: ComputedCarbs
        var iob: [IobResult]
        var currentTemp: TempBasal
        var customVariables: TrioCustomOrefVariables
        var determination: Determination
        var dynamicISFSkipped: Bool
    }

    /// Runs one oref cycle the way Trio does (Trio `OpenAPS.swift`): profile, autosens, meal, IOB, determine-basal.
    public static func determine(_ input: OrefInput) throws -> OrefOutput {
        let computed = try run(input)
        let determination = computed.determination

        func d(_ value: Decimal?) -> Double? { value.map { NSDecimalNumber(decimal: $0).doubleValue } }
        return OrefOutput(
            date: input.now,
            unitsPerHour: d(determination.rate),
            durationMinutes: d(determination.duration),
            microBolus: d(determination.units).flatMap { $0 > 0 ? $0 : nil },
            reason: determination.reason,
            eventualBG: determination.eventualBG.map(Double.init),
            minPredBG: d(determination.minPredBG),
            minGuardBG: d(determination.minGuardBG),
            insulinReq: d(determination.insulinReq),
            sensitivityRatio: d(determination.sensitivityRatio),
            iob: d(determination.iob),
            cob: d(determination.cob),
            isf: d(determination.isf),
            target: d(determination.current_target),
            forecasts: OrefOutput.Forecasts(
                iob: determination.predictions?.iob ?? [],
                cob: determination.predictions?.cob ?? [],
                uam: determination.predictions?.uam ?? [],
                zeroTemp: determination.predictions?.zt ?? []
            ),
            dynamicISFSkipped: computed.dynamicISFSkipped
        )
    }

    static func run(_ input: OrefInput) throws -> Run {
        guard !input.glucose.isEmpty else { throw OrefError.notEnoughData("no glucose") }
        guard !input.basal.isEmpty, !input.sensitivity.isEmpty, !input.carbRatio.isEmpty, !input.targets.isEmpty else {
            throw OrefError.notEnoughData("a therapy schedule is empty")
        }
        let clock = input.now

        var preferences = Preferences(input.preferences, input)
        let dynamicISFWanted = preferences.useNewFormula
        let haveDailyInsulin = (input.averageDailyDose ?? 0) > 0 && (input.totalDailyDose ?? 0) > 0
        if dynamicISFWanted, !haveDailyInsulin {
            preferences.useNewFormula = false
            preferences.sigmoid = false
        }

        let basalProfile = input.basal.map {
            BasalProfileEntry(start: timeString($0.minutes), minutes: $0.minutes, rate: dec($0.value))
        }
        let pumpSettings = PumpSettings(
            insulinActionCurve: dec(input.insulinActionHours),
            maxBolus: dec(input.maxBolus),
            maxBasal: dec(input.maxBasalRate)
        )
        let bgTargets = BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: input.targets.map {
            BGTargetEntry(low: dec($0.low, 0), high: dec($0.high, 0), start: timeString($0.minutes), offset: $0.minutes)
        })
        let isf = InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: input.sensitivity.map {
            InsulinSensitivityEntry(sensitivity: dec($0.value, 1), offset: $0.minutes, start: timeString($0.minutes))
        })
        let carbRatios = CarbRatios(units: .grams, schedule: input.carbRatio.map {
            CarbRatioEntry(start: timeString($0.minutes), offset: $0.minutes, ratio: dec($0.value, 1))
        })

        var profile = try ProfileGenerator.generate(
            pumpSettings: pumpSettings,
            bgTargets: bgTargets,
            basalProfile: basalProfile,
            isf: isf,
            preferences: preferences,
            carbRatios: carbRatios,
            tempTargets: [],
            clock: clock
        )
        profile.supportedBasalRates = input.supportedBasalRates.map { dec($0) }

        let pumpHistory = pumpHistoryEvents(input.doses, now: clock)
        let glucose = input.glucose.sorted { $0.date > $1.date }.map { reading -> BloodGlucose in
            let value = Int(reading.mgdL.rounded())
            return BloodGlucose(
                sgv: value,
                date: Decimal(reading.date.timeIntervalSince1970 * 1000).rounded(scale: 0),
                dateString: reading.date,
                glucose: value,
                type: "sgv"
            )
        }
        let carbs = input.carbs.filter { $0.date <= clock }.map {
            CarbsEntry(
                id: $0.id, createdAt: $0.date, actualDate: $0.date, carbs: dec($0.grams, 1),
                fat: nil, protein: nil, note: nil, enteredBy: "Loop", isFPU: false, fpuID: nil
            )
        }

        // Autosens: the lower of the 8- and 24-hour ratios, as Trio does.
        let precomputed = glucose.count >= 72 ? try IobHistory.calcTempTreatments(
            history: pumpHistory.map { $0.computedEvent() },
            profile: profile,
            clock: clock,
            autosens: nil,
            zeroTempDuration: nil
        ) : nil
        func autosens(_ maxDeviations: Int) throws -> Autosens {
            try AutosensGenerator.generate(
                glucose: glucose, pumpHistory: pumpHistory, basalProfile: basalProfile, profile: profile,
                carbs: carbs, tempTargets: [], maxDeviations: maxDeviations, clock: clock,
                precomputedTreatments: precomputed
            )
        }
        let ratio8h = try autosens(96)
        let ratio24h = try autosens(288)
        let autosensResult = ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h

        guard let meal = try MealGenerator.generate(
            pumpHistory: pumpHistory, profile: profile, basalProfile: basalProfile, clock: clock,
            carbHistory: carbs, glucoseHistory: glucose
        ) else { throw OrefError.notEnoughData("meal") }

        let iob = try IobGenerator.generate(
            history: pumpHistory.removingDuplicateSuspendResumeEvents(),
            profile: profile,
            clock: clock,
            autosens: autosensResult
        )

        let currentTemp = TempBasal(
            duration: Int((input.currentTemp?.minutesRemaining ?? 0).rounded()),
            rate: dec(input.currentTemp?.unitsPerHour ?? 0),
            temp: .absolute,
            timestamp: input.currentTemp?.start ?? clock
        )

        let total = input.totalDailyDose ?? 0
        let average = input.averageDailyDose ?? 0
        let weighted = preferences.weightPercentage * dec(total) + (1 - preferences.weightPercentage) * dec(average)
        let customVariables = TrioCustomOrefVariables(
            average_total_data: dec(average),
            weightedAverage: total > 0 ? weighted : 1,
            currentTDD: dec(total),
            past2hoursAverage: dec(total),
            date: clock,
            overridePercentage: dec(input.override?.percentage ?? 100, 0),
            useOverride: input.override != nil,
            duration: 0,
            unlimited: true,
            overrideTarget: dec(input.override?.target ?? 0, 0),
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: true,
            isf: true,
            cr: true,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: preferences.maxSMBBasalMinutes,
            uamMinutes: preferences.maxUAMSMBBasalMinutes
        )

        guard let determination = try DeterminationGenerator.generate(
            profile: profile,
            preferences: preferences,
            currentTemp: currentTemp,
            iobData: iob,
            mealData: meal,
            autosensData: autosensResult,
            reservoirData: dec(input.reservoir ?? 100),
            glucose: glucose,
            microBolusAllowed: true,
            trioCustomOrefVariables: customVariables,
            currentTime: clock
        ) else { throw OrefError.noDetermination }

        return Run(
            profile: profile,
            preferences: preferences,
            pumpHistory: pumpHistory,
            glucose: glucose,
            carbs: carbs,
            autosens8h: ratio8h,
            autosens24h: ratio24h,
            autosens: autosensResult,
            meal: meal,
            iob: iob,
            currentTemp: currentTemp,
            customVariables: customVariables,
            determination: determination,
            dynamicISFSkipped: dynamicISFWanted && !haveDailyInsulin
        )
    }

    /// Loop's doses as oref's pump history, newest first; a temp basal is a duration entry then a rate entry, as in Trio.
    static func pumpHistoryEvents(_ doses: [OrefInput.Dose], now: Date) -> [PumpHistoryEvent] {
        var events: [PumpHistoryEvent] = []
        for dose in doses {
            switch dose {
            case let .bolus(id, date, units, automatic):
                guard date <= now, units > 0 else { continue }
                events.append(PumpHistoryEvent(
                    id: id, type: .bolus, timestamp: date, amount: dec(units), duration: 0,
                    isSMB: automatic, isExternal: false
                ))
            case let .tempBasal(id, start, minutes, unitsPerHour):
                guard start <= now else { continue }
                events.append(PumpHistoryEvent(id: id, type: .tempBasalDuration, timestamp: start, durationMin: Int(minutes.rounded())))
                events.append(PumpHistoryEvent(id: "_\(id)", type: .tempBasal, timestamp: start, rate: dec(unitsPerHour), temp: .absolute))
            case let .suspend(id, start, end):
                guard start <= now else { continue }
                events.append(PumpHistoryEvent(id: id, type: .pumpSuspend, timestamp: start))
                if let end, end <= now {
                    events.append(PumpHistoryEvent(id: "\(id)-resume", type: .pumpResume, timestamp: end))
                }
            }
        }
        // Newest first; same-time entries keep their order (a temp's duration entry stays before its rate).
        return events.enumerated()
            .sorted { $0.element.timestamp != $1.element.timestamp ? $0.element.timestamp > $1.element.timestamp : $0.offset < $1.offset }
            .map(\.element)
    }

    static func timeString(_ minutes: Int) -> String {
        String(format: "%02d:%02d:00", minutes / 60, minutes % 60)
    }
}

private func dec(_ value: Double, _ scale: Int = 3) -> Decimal {
    Decimal(algorithmValue: value).rounded(scale: scale)
}

private extension Preferences {
    /// Trio's preferences from the stored oref settings plus what Loop already knows.
    init(_ p: OrefPreferences, _ input: OrefInput) {
        self.init()
        maxIOB = dec(p.maxIOB)
        maxCOB = dec(p.maxCOB)
        maxDailySafetyMultiplier = dec(p.maxDailySafetyMultiplier)
        currentBasalSafetyMultiplier = dec(p.currentBasalSafetyMultiplier)
        autosensMax = dec(p.autosensMax)
        autosensMin = dec(p.autosensMin)
        enableSMBAlways = p.enableSMBAlways
        enableSMBWithCOB = p.enableSMBWithCOB
        enableSMBWithTemptarget = p.enableSMBWithTemptarget
        enableSMBAfterCarbs = p.enableSMBAfterCarbs
        enableSMB_high_bg = p.enableSMBHighBG
        enableSMB_high_bg_target = dec(p.enableSMBHighBGTarget, 0)
        allowSMBWithHighTemptarget = p.allowSMBWithHighTemptarget
        maxSMBBasalMinutes = dec(p.maxSMBBasalMinutes, 0)
        enableUAM = p.enableUAM
        maxUAMSMBBasalMinutes = dec(p.maxUAMSMBBasalMinutes, 0)
        smbInterval = dec(p.smbInterval, 0)
        smbDeliveryRatio = dec(p.smbDeliveryRatio, 2)
        maxDeltaBGthreshold = dec(p.maxDeltaBGThreshold, 2)
        maxMealAbsorptionTime = dec(p.maxMealAbsorptionTime, 1)
        min5mCarbimpact = dec(p.min5mCarbImpact, 1)
        remainingCarbsFraction = dec(p.remainingCarbsFraction, 2)
        remainingCarbsCap = dec(p.remainingCarbsCap, 0)
        useNewFormula = p.useNewFormula
        sigmoid = p.sigmoid
        adjustmentFactor = dec(p.adjustmentFactor, 2)
        adjustmentFactorSigmoid = dec(p.adjustmentFactorSigmoid, 2)
        weightPercentage = dec(p.weightPercentage, 2)
        tddAdjBasal = p.tddAdjBasal
        highTemptargetRaisesSensitivity = p.highTemptargetRaisesSensitivity
        lowTemptargetLowersSensitivity = p.lowTemptargetLowersSensitivity
        sensitivityRaisesTarget = p.sensitivityRaisesTarget
        resistanceLowersTarget = p.resistanceLowersTarget
        halfBasalExerciseTarget = dec(p.halfBasalExerciseTarget, 0)
        // From Loop
        threshold_setting = dec(min(max(input.suspendThreshold, 60), 120), 0)
        bolusIncrement = dec(input.bolusIncrement)
        curve = input.insulinCurve == .ultraRapid ? .ultraRapid : .rapidActing
        useCustomPeakTime = false
    }
}
