# OrefAlgorithm

Trio's OpenAPS oref algorithm, packaged for Loop to offer as a second dosing algorithm.

- `Sources/OrefAlgorithm/Trio/` — unmodified copy from https://github.com/nightscout/Trio, tag v1.0.2
  (commit 0b29cd53415e7f0e668677749cad8daf81c68c2f): `Trio/Sources/APS/OpenAPSSwift`, and the models and
  helpers Trio's own `AlgorithmPackage/Package.swift` compiles with it. Trio is MIT licensed
  (`LICENSE-Trio.txt`). Refresh with `./copy-from-trio.sh <Trio clone>`; never edit these files here.
- `Sources/OrefAlgorithm/Oref.swift` — the only file written for Loop: plain input and output types, the
  oref settings Loop stores, and the one call that runs profile, IOB, meal, autosens and determine-basal in
  the order Trio runs them (Trio `OpenAPS.swift`).
- `Sources/OrefAlgorithm/OrefSettingsView.swift` — the settings screen (iOS only).
