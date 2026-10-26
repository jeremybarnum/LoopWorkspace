#if os(iOS)
import SwiftUI

/// Algorithm choice and oref's own settings, grouped as Trio's settings screens group them.
/// Glucose values are mg/dL.
public struct OrefSettingsView: View {
    @Binding var configuration: OrefConfiguration
    let lastOutput: OrefOutput?

    public init(configuration: Binding<OrefConfiguration>, lastOutput: OrefOutput?) {
        _configuration = configuration
        self.lastOutput = lastOutput
    }

    private var p: Binding<OrefPreferences> { $configuration.preferences }

    public var body: some View {
        Form {
            Section(footer: Text(algorithmFooter)) {
                Picker("Dosing algorithm", selection: $configuration.algorithm) {
                    Text("Loop").tag(DosingAlgorithm.loop)
                    Text("Loop, oref alongside").tag(DosingAlgorithm.orefShadow)
                    Text("oref (Trio)").tag(DosingAlgorithm.oref)
                }
            }

            if let output = lastOutput {
                Section(header: Text("Last oref decision")) {
                    LabeledContent("Time", value: output.date.formatted(date: .omitted, time: .shortened))
                    LabeledContent("Temp basal", value: output.unitsPerHour.map { "\(fmt($0)) U/h for \(fmt(output.durationMinutes ?? 0)) min" } ?? "no change")
                    LabeledContent("Micro-bolus", value: output.microBolus.map { "\(fmt($0)) U" } ?? "none")
                    LabeledContent("Eventual glucose", value: output.eventualBG.map { fmt($0) } ?? "–")
                    LabeledContent("Sensitivity ratio", value: output.sensitivityRatio.map { fmt($0) } ?? "–")
                    if output.dynamicISFSkipped {
                        Text("Dynamic ISF skipped: not enough insulin history yet").foregroundColor(.orange)
                    }
                    Text(output.reason).font(.footnote)
                }
            }

            Section(header: Text("Limits"), footer: Text("Max IOB 0 means oref never adds insulin above the scheduled basal. Max basal, max bolus, targets, ISF, carb ratios and the suspend threshold come from Loop's therapy settings.")) {
                stepper("Max IOB", p.maxIOB, "U", 0.5, 0...30)
                stepper("Max COB", p.maxCOB, "g", 10, 0...300)
                stepper("Max daily safety multiplier", p.maxDailySafetyMultiplier, "×", 0.5, 1...10)
                stepper("Current basal safety multiplier", p.currentBasalSafetyMultiplier, "×", 0.5, 1...10)
            }

            Section(header: Text("Insulin"), footer: Text("Trio's default is 10 hours and Trio recommends not changing it. oref's curve keeps its peak fixed, so 10 hours here acts much like Loop's 6. The curve follows the pump's insulin type.")) {
                stepper("Duration of insulin action", p.insulinActionHours, "h", 0.5, 5...10)
            }

            Section(header: Text("Autosens")) {
                stepper("Autosens max", p.autosensMax, "", 0.05, 1...2)
                stepper("Autosens min", p.autosensMin, "", 0.05, 0.5...1)
            }

            Section(header: Text("Super micro boluses (SMB)")) {
                Toggle("Always", isOn: p.enableSMBAlways)
                if !configuration.preferences.enableSMBAlways {
                    Toggle("With carbs on board", isOn: p.enableSMBWithCOB)
                    Toggle("With a temp target", isOn: p.enableSMBWithTemptarget)
                    Toggle("After carbs", isOn: p.enableSMBAfterCarbs)
                    Toggle("With high glucose", isOn: p.enableSMBHighBG)
                    if configuration.preferences.enableSMBHighBG {
                        stepper("High glucose above", p.enableSMBHighBGTarget, "mg/dL", 10, 100...300)
                    }
                }
                Toggle("With a high temp target", isOn: p.allowSMBWithHighTemptarget)
                stepper("Max SMB basal minutes", p.maxSMBBasalMinutes, "min", 15, 15...180)
                Toggle("Unannounced meals (UAM)", isOn: p.enableUAM)
                stepper("Max UAM SMB basal minutes", p.maxUAMSMBBasalMinutes, "min", 15, 15...180)
                stepper("SMB interval", p.smbInterval, "min", 1, 1...10)
                stepper("SMB delivery ratio", p.smbDeliveryRatio, "", 0.05, 0.3...0.7)
                stepper("Max delta glucose threshold", p.maxDeltaBGThreshold, "", 0.05, 0.2...0.4)
            }

            Section(header: Text("Meals")) {
                stepper("Max meal absorption time", p.maxMealAbsorptionTime, "h", 0.5, 4...10)
                stepper("Min 5-minute carb impact", p.min5mCarbImpact, "mg/dL", 1, 1...12)
                stepper("Remaining carbs fraction", p.remainingCarbsFraction, "", 0.1, 0...1)
                stepper("Remaining carbs cap", p.remainingCarbsCap, "g", 10, 0...120)
            }

            Section(header: Text("Dynamic ISF"), footer: Text("Uses the daily insulin totals Loop has stored; skipped until a day of history exists.")) {
                Toggle("Dynamic ISF", isOn: p.useNewFormula)
                if configuration.preferences.useNewFormula {
                    Toggle("Sigmoid formula", isOn: p.sigmoid)
                    if configuration.preferences.sigmoid {
                        stepper("Adjustment factor (sigmoid)", p.adjustmentFactorSigmoid, "", 0.05, 0.1...1)
                    } else {
                        stepper("Adjustment factor", p.adjustmentFactor, "", 0.05, 0.1...2)
                    }
                    stepper("Weighted average of daily insulin", p.weightPercentage, "", 0.05, 0.05...1)
                    Toggle("Adjust basal from daily insulin", isOn: p.tddAdjBasal)
                }
            }

            Section(header: Text("Target behaviour")) {
                Toggle("High temp target raises sensitivity", isOn: p.highTemptargetRaisesSensitivity)
                Toggle("Low temp target lowers sensitivity", isOn: p.lowTemptargetLowersSensitivity)
                Toggle("Sensitivity raises target", isOn: p.sensitivityRaisesTarget)
                Toggle("Resistance lowers target", isOn: p.resistanceLowersTarget)
                stepper("Half basal exercise target", p.halfBasalExerciseTarget, "mg/dL", 5, 100...200)
            }

            Section {
                Button("Restore Trio defaults", role: .destructive) { configuration.preferences = OrefPreferences() }
            }
        }
        .navigationTitle("Dosing Algorithm")
    }

    private var algorithmFooter: String {
        switch configuration.algorithm {
        case .loop: return "Loop's algorithm doses."
        case .orefShadow: return "Loop's algorithm doses. oref runs each cycle too and its decision is logged and shown below, but not given."
        case .oref: return "oref (Trio's algorithm) chooses temp basals and micro-boluses. Loop's forecast, warnings and bolus calculator are unchanged."
        }
    }

    private func stepper(_ title: String, _ value: Binding<Double>, _ unit: String, _ step: Double, _ range: ClosedRange<Double>) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text(unit.isEmpty ? fmt(value.wrappedValue) : "\(fmt(value.wrappedValue)) \(unit)").foregroundColor(.secondary)
            }
        }
    }

    private func fmt(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 2)))
    }
}
#endif
