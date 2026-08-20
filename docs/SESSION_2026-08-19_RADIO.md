# 2026-08-19 radio session — the complete result

One day, one pod, one sensor, ~22 instrumented reclaim ladders, and a natural experiment with the
phone powered off for 41 minutes. **Read this before any further radio work.** It settles four
hypotheses, kills three of mine, and leaves one genuinely open.

Method note: hypotheses were pre-registered in `POD_BLE_PREREGISTRATION.md` BEFORE the runs that
tested them, with named falsifiers. Where a result is scored below, the prediction predates the data.

---

## 1. THE HEADLINE — the phone was holding the pod, and that is why reclaims failed

### 1.1 Perfect separation: heard = connected, not heard = failed

Every ladder carrying the advert census, across the whole session: [MEAS]

| outcome | count | advert census |
|---|---|---|
| **FAILED** | **15** | `adverts=0 last=never rssi=-` — **every one** |
| **OK** | **7** | `adverts=1–2`, rssi −55 to −79 — **every one** |

**Zero exceptions in 22 ladders.** If the radio hears the pod, we connect. If it does not, we fail.
There is no case of "heard it and could not connect."

### 1.2 The natural experiment: phone off, effect gone; phone on, effect returns

| time | ladder | outcome | adverts | phone |
|---|---|---|---|---|
| 15:57–16:57 | L1, L1–L11 (13 ladders) | **ALL FAILED** | 0 | **ON** |
| **17:01:00** | — | *phone powered off* | — | — |
| **17:01:44** | L12 | **OK** in 6.3 s | 1, rssi −75 | OFF |
| 17:01:44 | L13 | OK | 1 | OFF |
| 17:01:49 | L14 | OK | 1 | OFF |
| 17:24:06 | L15 | FAILED | 0 | OFF |
| 17:24:34 | L16 | FAILED | 0 | OFF |
| 17:31:42 | L17, L18 | OK | 2, rssi −79 | OFF |
| 17:37:08 | L19, L20 | OK | 1, rssi −55 | OFF |
| **17:42** | — | *phone powered on* | — | — |
| **17:42:11** | L21 | **FAILED** | 0 | **ON** |

```
phone ON  : 0 / 13 succeeded   (0%)
phone OFF : 7 /  9 succeeded  (78%)
```

**The first success came 44 SECONDS after the phone powered off, following thirteen consecutive
failures. The first failure after it came back was 11 SECONDS later.** Treatment removed, effect
gone; treatment restored, effect returns — within seconds in both directions.

The two phone-off failures (L15, L16 at 17:24) sit inside the sensor outage described in §3, when no
cycles had run for 20+ minutes and the pod was cold — a separately documented failure regime.
Excluding them: **0/13 with the phone on, 7/7 with it off.**

### 1.3 The mechanism, caught in the phone's own ledger

While `released=true` for the entire loan, the phone's connect counters climbed: [MEAS]

```
16:25:47  GRANT — releasing pod BLE     issued=3 ok=3
16:26:44  released=true                  issued=4 ok=4   <- connect, SUCCEEDED
16:29:49  released=true                  issued=5 ok=5   <- connect, SUCCEEDED
16:31:21  GRANT (e137) — releasing       issued=6 ok=6
16:34:49  released=true                  issued=7 ok=7
```

**The phone connects to the pod every 2–3 minutes during a loan, and every connect succeeds.** A pod
in a connection does not advertise. Hence `adverts=0`, hence the 28-second failures.

It also retro-explains a tell we stared at for two days: `settle: link up +0.0s` the instant the watch
gives up. A cold Omnipod connect takes ~17 s. **`+0.0s` never meant "the phone reconnected fast" — it
meant "the phone never let go."**

### 1.4 Why this happens: OmnipodKit has no concept of a loan

`grep` for `loanActive` / `loanInProgress` / `suspendForLoan` in OmnipodKit returns **nothing**. The
isolation is achieved INDIRECTLY, by emptying `autoConnectIDs` and `devices` so the automatic paths
(`autoReconnect`, the heartbeat probe and its re-arm) find nothing to act on. That covers the paths
that consult those collections and cannot cover any other, **because there is no flag to consult.**

**Not yet known: WHICH path connects.** The `via:` reason is captured by the
`** CONNECT WHILE ON LOAN **` alarm added this session, but `omnipodLogDeviceEvent` routes to LoopKit's
device-communication store rather than `PhoneLog`, so on the PHONE the alarm lands somewhere
unreadable. Fixing that routing names the mechanism in one run. **This is the single highest-value
next step.**

---

## 2. Hypothesis scoreboard

| # | hypothesis | verdict |
|---|---|---|
| H1 | The G7's scanning starves the pod's connect | **DEAD** — failures span `g7direct` 26 s to 1254 s |
| H2 | Leaked connect intents exhaust the connection table | **DEAD** — `ORPHANED=1` across SUCCESSFUL connects; a refusal occurred at `ORPHANED=0` |
| H3 | Two of our connect paths race; CoreBluetooth refuses the duplicate | **REAL but MINOR** — n=2, and both refusals happened inside ladders that SUCCEEDED. Guard shipped; `suppressed=0` all session |
| H4 | The dominant failure is DISCOVERY, not connection | **CONFIRMED** — 22/22 perfect separation |
| H5 | The pod is invisible because something still holds it | **CONFIRMED — it is the PHONE** |
| H6 | watchOS throttles our background scan | **DEAD** — 0 `APP BACKGROUND` events in the entire ladder window; there were never any background ladders |
| H7 | The pod's advertising interval exceeds the 28 s budget | **UNTESTABLE from this data** — see below |
| H8 | Powering the phone off frees the pod | **CONFIRMED** — 0/13 vs 7/9, flipping within 44 s and reverting within 11 s |
| H9 | Why Dexcom drops after the phone powers off | **Collector-slot story NOT supported** — see §3 |

**On H7:** advert counts on successes are 1–2, which looks like a low advertising rate — but the census
is **censored by early termination**: the ladder stops as soon as it connects. The counts measure how
long we listened, not how often the pod speaks. H7 cannot be scored from this data and the low numbers
must not be read as evidence for it.

---

## 3. The sensor outage — both collectors, not one

Pre-registered discriminator: D2W's cadence across the boundary, visible in OUR log because the OS
reports every D2W connection. [MEAS]

```
17:01:36  D2W-CONNECT  our-reading 120     <- phone powered off at 17:01:00
[ 22-minute gap: 17:06, 17:11, 17:16, 17:21 all missed ]
17:23:36  D2W-CONNECT  our-reading 100     <- both resume TOGETHER
```

**Both collectors went dark simultaneously and recovered together.** By the pre-registered branches
that rules out collector-slot allocation (Jeremy's 40%).

But it is not coincidence either (Jeremy's 35%): the last good reading was **36 seconds after the
phone powered off**, and recovery came **22.6 minutes later**, matching the 25–30 minute constant
Jeremy remembered from earlier sessions.

**And the watch's radio was fine throughout** — pod ladder L12 succeeded at 17:01:44, inside the gap.
So this was not a watch-side outage. The sensor stopped talking to both of its remaining collectors
when the third vanished abruptly.

**This lands in Jeremy's 20% "something else we don't know yet" — the only category that was right.**

### 3.1 What IS established about the outage

- **It is a timeout, not a re-negotiation.** Recovery happened with the phone still off, so healing is
  not triggered by the phone's return. (Pre-registered as H9a; the restoration branch is dead.)
- **Everything is quantized to the sensor's 5-minute grid:** ~2 windows before D2W declares signal
  loss, ~4–5 windows to recovery. Nothing at an odd interval, which fits a designed timeout.
- **Dexcom's own remedy is a Bluetooth toggle plus a 10-minute wait** — half the natural heal. If both
  numbers are right, the toggle roughly halves recovery, which coincidence does not predict. Untested.

### 3.2 Why it matters commercially

Phone-off exercise is the product's core use case. A ~22-minute CGM gap beginning ~36 seconds after
the phone is switched off is not an edge case — it is the first 20 minutes of every such session.

---

## 4. The hand-back wedge, and its blast radius

- **A phone REBOOT resets `WCSession.isWatchAppInstalled` to false.** It was true at 16:23:28, survived
  41 minutes of the phone being POWERED OFF, and came back false only after boot. The break is the boot
  cycle, not the absence.
- **With it false, WCSession QUEUES every message.** The hand-back ack never lands, the watch re-offers
  every 15 s indefinitely, and the loan cannot end. **Any user who reboots mid-loan hits this.**
- **Direction, because it inverts easily:** watch → phone WORKS (`offer RX` logged once per resend);
  phone → watch fails (`send handbackAck path=queued`). From the wrist the two are indistinguishable.
- **Restarting the PHONE app makes the WATCH app quit** — observed directly, mechanism unknown.
- **The watch app then CRASH-LOOPS on relaunch.**
- **The settle can WEDGE rather than progress.** A force-quit of the phone app produced an instantly
  live pod pill. Had the pod truly been unreachable, a restart would have had to re-acquire it. So the
  state machine was stuck, not working.
- **`isWatchAppInstalled` is SYSTEM state, not app state** — force-quitting both apps does not fix it,
  because neither owns the flag.

---

## 5. Retractions — claims made and withdrawn this session

Recorded because each was argued confidently before it was checked.

1. **"The G7's near-continuous scanning is the disease"** (2026-08-18 headline). Wrong.
2. **"Connection-slot exhaustion via leaked intents"** — the theory the whole intent-ledger build was
   made to test. The ledger killed it: orphans stood across successful connects.
3. **"`recreateCentral` is the prime suspect; cancel-before-drop is the fix."** It would have changed
   nothing.
4. **"The crash loop is Xcode's debug-dylib split."** `ENABLE_DEBUG_DYLIB = NO` produced a verified
   single binary and the crash loop returned on that build. Better hypothesis, untested: the watch app
   crash-loops restoring a WEDGED LOAN STATE (13:00 in "returning records", 17:45 in "ending").
5. **"Install order determines `appInstalled`."** Proposed on one observation, refuted within three
   hours by the same order producing the opposite result.
6. **"Ladders succeeded when the app was foregrounded."** A measurement error: `APP FOREGROUND` is a
   TRANSITION, and time-since-transition was read as "backgrounded". Counting `APP BACKGROUND` — the
   field logged right beside it — gives zero background ladders.
7. **"`EAGER_LINKING = NO` means the arm64_32 phantom cannot recur."** The setting was project-scoped;
   seven TBDs regenerated from other projects hours later.
8. **"The settle at 48 s is genuinely working at it rather than stuck."** The force-quit showed it was
   wedged.

**The pattern worth naming:** six of the eight were about CONNECTING, or about a build artifact, and
were argued from mechanism rather than measurement. The two that survived contact with data (H4, H5)
came from classifying every ladder and reading the phone's own counters.

---

## 6. What is open

1. **WHICH phone path connects during a loan.** Route the `CONNECT WHILE ON LOAN` alarm to `PhoneLog`.
   One run answers it. **Highest value.**
2. **The interlock.** OmnipodKit needs a real loan flag, not isolation-by-empty-collection. Design once
   (1) names the offender.
3. **The sensor outage mechanism** (§3) — in the unknown category, and commercially significant.
4. **The wedged-state crash loop** — a crash log from Devices and Simulators would name it, and on a
   single binary the frame points at real code.
5. **Whether BT-off-only (no reboot) is a better experimental rig.** The registration breaks on boot,
   so radios-off should avoid the wedge; WCSession may survive on Wi-Fi, keeping observability.
6. **H7** — needs an uncensored advert census (keep counting after connect, or run a scan-only probe).

---

# ADDENDUM 2026-08-20 00:15 — H5 IS NOT THE EXPLANATION. The watch cannot HEAR the pod.

**This overturns §1 of this document.** Read it before acting on anything above.

Loan e141 ran with the interlock active. Every ladder's advert census was compared against the Mac
observer — a passive third party in the same room, which is neither app and never connects. [MEAS]

| ladder | window | watch heard | MAC heard |
|---|---|---|---|
| L6 | 23:51:40→23:52:08 | **0** | **15** |
| L7 | 23:52:08→23:52:37 | **0** | 7 |
| L8 | 23:56:59→23:57:28 | **0** | 15 |
| L9 | 23:57:28→23:57:56 | **0** | 12 |
| L10 | 00:01:38→00:02:06 | **0** | 11 |
| L11 | 00:02:06→00:02:34 | **0** | 13 |
| L12 | 00:06:38→00:07:07 | **0** | 10 |
| L13 | 00:07:07→00:07:32 | **0** | 8 |

**The pod was advertising throughout every failure.** `adverts=0` does not mean the pod was silent; it
means OUR RADIO DID NOT DELIVER what was in the air.

**The phone is exonerated, by construction.** L6–L11 ran while the phone was inside a FARADAY CAGE. It
could not reach the pod. The ladders failed identically anyway.

## What this does to the day's conclusions

- **H5 ("the phone holds the pod, so it stops advertising") — NOT the explanation.** It was inferred
  from `adverts=0` plus a phone-on/off correlation. The census only ever measured OUR RECEIVER, and the
  correlation does not survive a window where the phone was RF-isolated.
- **The 0/13 vs 7/9 phone-on/off result stands as an observation and falls as a mechanism.** Something
  covaried with it; the pod's availability did not.
- **The interlock is still correct and still worth keeping.** It refused four `freshConnect` attempts
  during e141 — the phone genuinely does reach for a pod it has lent away, which is a real defect. It
  simply is not what breaks reclaims.
- **H4 survives in stronger form.** The failure IS at the discovery stage — but the stage fails on the
  RECEIVE side, inside our own process, not because the pod is unavailable.

## The lead, and it is a good one

The only two ladders that SUCCEEDED (L1, L2 — `adverts=9`) both ran at **`g7direct=never`**: before our
G7 stack had connected at all. Every ladder after the G7 went live failed at `adverts=0`.

**Hypothesis (untested): two CBCentralManagers scanning in one watchOS process, and only one of them
receiving.** `G7SensorKit` and `OmnipodKit` each run their own central. That would explain tonight
exactly, and it revives 2026-08-18's H1 in a far better-evidenced form — not the G7 starving our
CONNECT, but starving our SCAN's advertisement delivery.

**Cheap tests, in order:**
1. Run a loan with the G7 stack disabled and see whether ladders stop failing.
2. Log `centralManager.isScanning` on the pod central at every failed read — is our scan even running?
3. Have the pod central log EVERY `didDiscover` (any peripheral, not just ours). If it sees nothing at
   all while the Mac sees traffic, the central is starved, not mis-filtered.

**Method note.** Every wrong turn today came from inferring the world from one device's view. The Mac
observer settled in one query what two days of watch-side logs could not, because it could see what was
actually in the air. Keep it running for every future run.


---

# CORRECTION 2026-08-20 (review) — the addendum's "perfect separation" was likely CIRCULAR

The advert census behind the 15-failures-at-adverts=0 table counted only pods in `autoConnectIDs` —
inserted on ADOPT, removed by the RELEASE path. A failed ladder (post-release, never adopted) was
therefore mechanically blind, whatever the radio heard: `adverts>0 ⟺ adopted ⟺ success` is close to
a tautology. **"The watch cannot HEAR the pod" is UNSUPPORTED.** What survives: the pod was available
(Mac observer) and the ladders failed — mechanism unknown. H14 rested partly on that table and is
downgraded accordingly; the census now counts by address match, and the intent ledger (never
membership-gated) — e.g. the L10 self-cancelled connect — is the better evidence stream.
