# Upstream PR candidates

Defects found here that are **not ours** — they exist in stock LoopKit/Loop and would be fixed
upstream rather than in the Sport Mode line. Started 2026-08-18.

Rules for this list: each entry names the file:line, says how it was found, and states what is
verified versus inferred. An entry that cannot be reproduced against stock does not belong here.

---

## 1. Launch trap: `askUserToConfirmLoopReset()` runs outside its state guard

**Severity: high — reproducible crash on every cold boot before first unlock.**

`LoopAppManager.resumeLaunch()` gates every launch step on `state`, then calls
`askUserToConfirmLoopReset()` **unconditionally** as the last statement
(`Loop/Managers/LoopAppManager.swift:181`):

```swift
if state == .checkProtectedDataAvailable { checkProtectedDataAvailable() }
if state == .launchManagers            { await launchManagers() }
…
askUserToConfirmLoopReset()          // ← not guarded
```

`checkProtectedDataAvailable()` returns early without advancing `state` when protected data is
unavailable (`:187-191`, logging "Protected data not available; deferring launch…"). So
`launchManagers()` is skipped, `resetLoopManager` is never assigned (`:203`), and the trailing
call force-unwraps a nil implicitly-unwrapped optional (`:91`, `:1001`).

**Repro:** reboot the phone; let Loop be background-launched before the first unlock.

**Evidence (verified, not inferred):** symbolicated crash from 2026-08-18 18:06:05, dSYM UUID
matched exactly (`C64C5886-43AD-39D4-8919-F18C0F1D428F`). Crashing frame is
`LoopAppManager.resumeLaunch() (LoopAppManager.swift:181)`. Report carries
`wasUnlockedSinceBoot: 0`, `isLocked: 1`, `procRole: "Non UI"`, `EXC_BREAKPOINT`/`brk 1` on
`com.apple.main-thread`, dead ~1.2 s after launch. Two occurrences the same evening.

**Provenance:** `de602bb5 [LOOP-4648] Smarter Loop Reset State`, Cameron Ingham, 2023-05-18.

**Fix shape:** move the call inside the `.launchHomeScreen` branch, or guard it on the launch
having completed. Deferral is correct; it just needs to stop the function.

---

## 2. Insulin displayed to three decimals — a precision no pump can deliver

**Severity: low, but user-visible everywhere insulin is shown.**

`QuantityFormatter(for: .internationalUnit)` returns `maxFractionDigits = 3`
(`LoopKit/QuantityFormatter.swift:200-201`), so IOB renders as e.g. **`1.427 U`**. Pod
granularity is 0.05 U (`Pod.pulseSize`), so the last two digits assert precision the hardware
does not have and no dose can act on.

Noticed in the field 2026-08-18 ("active insulin 1.427 — interesting that this is a next dev
bug"). The same formatter produced `REC: 2.191 U` on our watch, which we fixed on our side by
rounding at source; the phone's IOB is a pure display issue.

**Fix shape:** two fraction digits for insulin display, matching deliverable resolution. Needs a
check of every `.internationalUnit` display site rather than a blanket change to the formatter,
since some call sites may want the extra digits for diagnostics.

---

## 3. Retrospective-correction integral: already fixed upstream — recorded so it is not re-raised

**Not a PR. Closed.**

`IntegralRetrospectiveCorrection` zeroes its accumulator and replays from the discrepancy array
on every call (`LoopAlgorithm/…/IntegralRetrospectiveCorrection.swift:121`, `:139`), so it holds
no cross-cycle state. Dragan's original accumulated and that was raised against it at the time;
the non-accumulating form is what shipped in `2ccdaab` (Feb 2024). Verified in code, not from
memory. See `PREDICTION_CONCEPTS_AND_IMPLEMENTATIONS.md` §1.4.

---

## Candidates needing more work before they are PR-shaped

- **Display refresh on the loop's error path.** Our fork calls `updateDisplayState` after the
  do/catch so it runs when a cycle errors (`13fe656f`). Upstream may only refresh on success, in
  which case the phone's status screen freezes through a run of failed enacts — the same class we
  just fixed on the watch. NOT yet verified against unmodified upstream.
- **Foreground banner allow-list.** `LoopAppManager.userNotificationCenter(_:willPresent:)`
  (`:910`) grants `.banner` only to an enumerated set of identifiers; everything else is
  explicitly denied a foreground banner. Any notification added later is silently non-bannering
  unless someone remembers to extend the list. Arguably by design, but it is a trap.
