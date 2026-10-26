#!/bin/zsh
# Refresh Sources/OrefAlgorithm/Trio from a Trio checkout: the same files Trio's own
# AlgorithmPackage compiles. Usage: ./copy-from-trio.sh <path to Trio clone>
set -e
T=${1:?path to a nightscout/Trio clone}
D=${0:A:h}/Sources/OrefAlgorithm/Trio
rm -rf $D && mkdir -p $D/APS/Extensions $D/Models $D/Helpers
rsync -a $T/Trio/Sources/APS/OpenAPSSwift $D/APS/
cp $T/Trio/Sources/APS/Extensions/DecimalExtensions.swift $D/APS/Extensions/
for m in Autosens BGTargets BasalProfileEntry BloodGlucose CarbRatios CarbsEntry Determination IOBEntry \
    InsulinSensitivities Override Preferences PumpHistoryEvent PumpSettings TDD TempBasal TempTarget TrioCustomOrefVariables; do
  cp $T/Trio/Sources/Models/$m.swift $D/Models/
done
for h in ConvenienceExtensions Decimal+Extensions Formatters JSON Rounding String+Extensions TherapySettingsUtil \
    TimeInterval+Convenience; do
  cp "$T/Trio/Sources/Helpers/$h.swift" $D/Helpers/
done
cp $T/LICENSE.txt ${0:A:h}/LICENSE-Trio.txt
echo "Copied from Trio $(git -C $T describe --tags --always) ($(git -C $T rev-parse --short HEAD)); update README.md"
