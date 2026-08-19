# The BLE ecosystem — what is physically true, what we designed, what we know

**Status: REVISED 2026-08-19 (afternoon), after Jeremy's markup AND after the connect-intent ledger
reported from the field.** Read Part 4 first: it is the measured part, and it kills two hypotheses the
earlier parts of this document argue for. Parts 1–3 are background and are still sound; where they
conflict with Part 4, Part 4 wins. Jeremy's inline `JB` comments are answered in `>` blocks beneath
them; his challenge on the sensor clock (2.1a) was correct and that section is rewritten.

The step-back document: one model of the
radio ecosystem, stated plainly enough to be wrong in public, with every claim graded. Scope is
the STANDALONE WATCH ecosystem — watch radio, G7 sensor, pod. The phone's radio matters only at
grant/hand-back boundaries and is deliberately out of scope here.

Grading used throughout:
- **[PHYS]** physics / BLE-spec level. Would bet the project on it.
- **[APPLE]** Apple-platform behaviour, documented or well-established. High confidence, but
  Apple can change it and some of it is undocumented folklore.
- **[MEAS]** measured in our own logs, with the citation.
- **[HYP]** our current best hypothesis. Falsifiable, test named.
- **[UNK]** genuinely unknown. Do not build on these.

---

# Part 1 — The hardware truth

## 1.1 How many radios does the watch actually have?

**[APPLE]** One 2.4 GHz Bluetooth radio, on the combined Apple wireless chip, shared by
Bluetooth Classic and BLE, **time-multiplexed**. Wi-Fi is on the same chip (separate front-end,
coexistence-scheduled, same antenna real estate). Cellular (on the SE 3 cellular model) is a
separate radio entirely.

So the honest picture: everything Bluetooth on the watch — the phone link, AirPods audio, the
G7, the pod — is **one radio being time-sliced**. "Concurrent connections" means the scheduler
interleaves them, not that they run in parallel.

## 1.2 BLE vs Classic Bluetooth — the difference that matters here

**[PHYS]** They are different protocols sharing the radio:

- **Classic (BR/EDR)** — what AirPods audio streams over. Near-continuous radio occupancy while
  active. Heavy.
- **BLE** — what the G7, the pod, and the watch↔phone link use. A BLE "connection" is NOT a
  continuous circuit: it is a series of brief scheduled exchanges ("connection events") at a
  negotiated interval (7.5 ms–4 s). Between events, the radio is free.

**The consequence, and it is the central one for our design: an ESTABLISHED BLE connection is
cheap.** It occupies microseconds per interval. Ten held BLE links can coexist on one radio
easily. What is expensive is **scanning** (receiver on for long windows) and what is *scarce* is
**the connection table** (below). This matches our prior field evidence exactly: the 263-cycle
census showed an established G7 link coexisting with pod traffic, and the 2026-08-10 toggle
showed a held pod link starves G7 *acquisition* only, never its steady state.

## 1.3 Advertisement vs connection vs "hold" — the vocabulary, pinned

- **Advertising** [PHYS]: the peripheral broadcasts short packets on 3 advertising channels.
  Anyone scanning can hear it. This is how a connection STARTS and the only time it can start.
- **Scanning** [PHYS]: a central holds its receiver open listening for adverts. Radio-expensive
  for the scanner, free for everyone else. **A scan holds no connection and no slot.**
- **Connecting (pending intent)** [APPLE]: `CBCentralManager.connect()` never times out. The
  system scans on the caller's behalf and completes the connection when it hears the target's
  advert. A pending intent is bookkeeping in bluetoothd **and counts against system connection
  resources** — this is the load-bearing claim of the current investigation, graded [HYP] at the
  system level and now instrumented (the intent ledger).
- **Connected / "held link"** [PHYS]: the cheap state. Periodic connection events, microseconds
  each. Can be held for hours at trivial radio cost.
- **The connection table** [APPLE/MEAS]: the system-wide limit whose exhaustion is
  `CBErrorDomain Code=11` — literally `CBError.connectionLimitReached`, "The system has reached
  the maximum number of connections." It is shared by **every app and system daemon on the
  device**. We have measured it refusing the pod (07:31:43) and the G7 (08:26:40 ×8)
  simultaneously, and measured that a Bluetooth toggle — which resets the table — clears it.
  The numeric limit is undocumented. [UNK]

**Answering the intuition directly:** "active vs passive" maps to *scanning vs holding*, and the
surprise is that it is backwards from the intuition — **holding is the passive-cheap state;
acquiring is the active-expensive one.** A design that repeatedly drops and re-acquires converts
a cheap standing cost into an expensive recurring one, and each acquisition risks a table entry.

---

# Part 2 — The three devices, modelled

## 2.1 The G7 sensor

**[MEAS]** Duty-cycled, hard: it wakes roughly every 5 minutes, advertises, accepts
connection(s), delivers the reading (plus backfill), and disconnects after ~10–11 s
(didConnect 08:26:38 → didDisconnect 08:26:49; same shape at 22:26 the night before). Between
windows it is genuinely unconnectable — not silent-but-listening; OFF to the world.

**So "a standing connection to the G7" does not exist and cannot.** What *looks* standing is
three different things layered:
1. the **bond/pairing** (persistent, not a connection),
2. **our scan**, running most of the 5-minute gap waiting for the next window ([MEAS]: scan
   STARTED → ad DISCOVERED gaps of 4m37s, 4m46s), and
3. the ~10 s of actual connection each cycle.

### 2.1a "If it's bonded and the grid is known, why scan at all?"

The obvious question, and the answer has three parts. (Jeremy, 2026-08-19.)

**A bond lets you skip PAIRING, not skip DISCOVERY.** [PHYS] There is no "call the sensor at
time T" primitive in BLE. A connection can only be initiated by answering an advertisement, in
the milliseconds after it is heard, and the initiator must have its receiver open at that moment.
Even `connect()`-and-wait is a scan underneath — bluetoothd listens for that address on your
behalf. So *someone* must be listening during the sensor's window, bond or no bond. Knowing the
schedule does not remove the doorway; it only tells you when to stand in it.

**The sensor's clock is EXACT. My "drift" claim was wrong — Jeremy challenged it and the
sensor's own stamps settle it.** [MEAS]

Every `G7GlucoseMessage` carries the sensor's own `sequence` and `messageTimestamp`. Across
**281 readings** spanning 23.4 hours:

```
seq 2188  ts 655699   at 2026-08-18 09:21:40
seq 2469  ts 739999   at 2026-08-19 08:46:39

Δseq = 281 readings
Δts  = 84300 sensor-seconds  →  300.0000 s per reading, exactly
Δwall = 84299 s              →  drift +1 s over 23.4 h = 11.9 ppm
                             →  ~10 s over a 10-day sensor life
```

So the grid is exact to a part in 84,000, and the ~10 s of lifetime drift could as easily be
OUR clock as the sensor's. Jeremy's hypothesis — "a solid internal clock, a few seconds over ten
days, predictable within seconds" — is confirmed. There is no cumulative drift to guard against.

**What DOES vary is the per-window jitter, and it is the real constraint.** Consecutive stamp
deltas run 300, 299, 302, 298, **310, 293** — so an individual window can land ±10 s off the
grid even though the long-run rate is exact. The 4m37s / 4m46s discovery gaps I cited as
evidence of drift were nothing of the kind: they are *discovery* jitter — when in an open window
our scan happened to catch the advert — sitting on top of a perfectly stable grid.

**Consequence for the design: the guard band is set by window jitter (~±10 s), not by drift.**
Something like a 20–30 s arm around the predicted instant, re-anchored on every reading, is
enough — tighter than crude's 45 s, and an order of magnitude tighter than the ~270 s we scan
today. And because the grid never slips, one good reading re-anchors the whole schedule.

**The guard band CAN be small, and crude proved it.** [MEAS] That is exactly crude's recipe —
"scan is the primitive, fresh lead-time arming, 300−45 geometry": arm ~45 s before the predicted
window instead of scanning ~270 s. Validated overnight in closed loop. So the question is not
whether scheduled scanning works; it is why next-dev does not do it. The answer is unremarkable:
stock G7SensorKit was written for the **phone**, where continuous scanning costs nothing anyone
measures and never-miss-a-window robustness (drift, restarts, warm-up, backfill, resync) beats
efficiency. We inherited phone economics onto a watch whose receiver is shared with pod
acquisition.

**And next-dev has a doorway that needs no scan of ours at all.** [MEAS] Trigger b —
connection-event monitoring — fires when the *Dexcom app's* link to the sensor comes up
(`connection-event CONNECT DXCMqL — handling`), letting us connect into an already-open window
at Dexcom's expense rather than our own. Trigger c (our scan) exists for first contact after
relaunch and as insurance when the Dexcom app misses a window.

**So the preference ordering should be: connection events first, guard-band scheduled scan
second, continuous scan never.**

*JB - okay this is important stuff, but it strikes me that b is very good and powerful and we should have a strong bias for using it.  And probably instrument things to reflect that bias rather than a big fallback tree that means we dno't actually know what's happening.  Mabe that's already true.  * 

> **Answered.** Agreed, and (b) is now the design bias, not a fallback. Two reasons it is stronger
> than I first wrote it: it costs no receiver time at all (the OS tells us), and Jeremy's clock
> finding means one reading anchors the whole future grid, so (b) plus a narrow guard band is
> sufficient — the fallback tree exists only for the first acquisition after launch. The instrumenting
> point is taken: the census should report WHICH doorway produced each reading, so the bias is
> visible in the data rather than asserted here.

**Important caveat, or this becomes the fourth wrong theory:** shrinking the G7 scan is a real
win in receiver time and coexistence pressure, but it probably does **not** touch the Code=11
disease. Code=11 is a *connection-table* error and **a scan holds no table entry**. If we fixed
only the scan and left the intent churn alone, the expectation is that the lockups continue.
Scan geometry and intent hygiene are separate problems that happen to share a symptom. *JB understood.  Let me read to the end, but I have some questions about Code = 11*

**[Jeremy/ground-truth]** The sensor accepts up to **three** collectors. On the watch during a
window, plausibly two of those are in play: the Dexcom watch app's own link and ours (the
"piggyback"). Whether the sensor serves collectors simultaneously or sequentially within one
window: [UNK], and it matters for worst-case window timing. **JB good point about that.  I could probably do an experiment by staring at the D2W app in the watch and noting when it updates.  Important to note - the statement of 2 connectors is true when the phone is off.  WHen it's on, we're using all 3 - phone, D2W, Sport mode.  I think, I'm not sure*

> **Answered.** The D2W-staring experiment would work, and there is a cheaper version: we already log
> `connection-event CONNECT DXCMqL` every time the OS sees D2W connect, so D2W's rhythm is already in
> our logs without anyone watching a screen. Worth extracting rather than observing.
>
> Jeremy's correction on collector count is important and is now carried into 4.0: **2 collectors is
> the phone-OFF case; with the phone on it is phone + D2W + Sport Mode = 3**, which is exactly the
> documented sensor limit. That is a different ceiling from the watch-side `Code=11` one — sensor-side
> (peripheral refuses) versus watch-side (our own connection table). Both are real; they are not the
> same constraint, and conflating them cost us a day.

**The 2026-08-19 "53-minute outage" is UNVERIFIED as a sensor fact.** `g7direct=3207s` says OUR
direct link was absent; phone-relay readings kept arriving throughout, and the D2W control —
what Dexcom's own watch app showed — was not checked (Jeremy wasn't wearing eyes on it).
Standing rule applies: never theorise a sensor outage without the D2W control. What we CAN say
[MEAS] is that our G7 connects were refused with Code=11 during part of that window, which is a
*watch-side* statement, not a sensor-side one.

## 2.2 The pod

**[MEAS/APPLE]** The pod is built for a **standing connection**: stock Loop's phone holds one
continuously, and the pod's whole protocol assumes an owner. When unconnected:
- it **advertises** (we log its adverts: svcUUIDs [4024, …], and scan-adopt works off them),
- after ~3 minutes without contact it self-disconnects/idles and becomes harder to catch
  ([MEAS], the 578s/518s/259s idle observations — the "gentle bid is a coin-flip" note),
- it is NOT dead: the phone connected to it in **1–3 s** at both hand-backs on 2026-08-19,
  seconds after 9 consecutive watch reclaims had failed for 20 minutes. **The pod was
  connectable the whole time. The watch was the sick party.** [MEAS — this is the single most
  diagnostic fact of the whole investigation]

**JB OKay, but I have a question - am I right that next dev switched from standing connection to on demand? do we know why? notably, pods running out of battery are not a thing.  But, there is some work going on for the next omnipod product**

> **Answered — and the "why" is unflattering.** Yes: next-dev runs connect-on-demand
> (`BluetoothManager.connectOnDemandEnabled`), where the pod is left disconnected between commands and
> observed via advertisements. The justification in the code is radio economy — not holding a link the
> pod does not need. Jeremy's point that pod battery is not a constraint removes the strongest reason
> for it, and 1.2 says a held link is nearly free anyway. So on-demand is buying us very little and
> costing us ~12 acquisitions/hour, each of which is a chance to hit exactly the race in 4.1.
> That is why "hold the link for the life of a loan" is item 4 in Part 5. [Design intent read from
> code + comments, not from a written rationale — no design doc for the switch exists in this tree.]

## 2.3 The watch

**Jeremy was right that the earlier list had too many actors — it double-counted, and here is the
corrected one.** "The system's own Dexcom bond" and "the Dexcom watch app's G7 link" were the same
thing seen twice, and "our G7 central" and "Sport Mode's G7 connection" were also the same thing.
The bond is not a connection at all (1.3): it is stored keys, and it persists whether anything is
connected or not. What actually occupies the radio and the connection table:

| actor | what it is | counts against our quota? |
|---|---|---|
| phone link | the watch↔iPhone pairing | no — system-managed |
| AirPods | Classic Bluetooth, heavy while streaming | no — different transport, but shares the radio |
| Dexcom's own watch app (D2W) | a real G7 link, held ~11 s per window | **ambiguous** — per-app quota says no, WorkOutDoors says maybe |
| **our G7 central** (`G7SensorKit`) | our link to the sensor | **YES** |
| **our pod central(s)** (`OmnipodKit`) | our link to the pod | **YES** |

The last two are in one process and are the whole of our budget (4.0).

**On "multiple pod centrals seems bad and possibly unnecessary" — agreed, and it is now also
pointless.** `escalateLoanReclaim` recreates the pod central by design, on the theory that dropping
it clears a stalled pending connect. The ledger tested that theory and killed it (4.1): orphaned
intents did not hold slots, and connects succeeded with an orphan standing. So the central rebuild is
buying nothing we can measure while adding a class of state we cannot reason about. It should be
reconsidered — not as a slot fix, which it is not, but on the grounds that it was justified by a
belief that turned out to be false.

**[MEAS]** The failure mode is watch-local and cumulative: early-session reclaims succeed,
late-session ones fail 9/9, the G7 gets refused too, and only a table reset (BT toggle)
recovers. Nothing about the pod or the sensor changes across that arc.

---

# Part 3 — What we built on top of this, in three generations

| | **crude** (`g7-build-next`) | **pure** (`SportMode`) | **next-dev** (port) |
|---|---|---|---|
| G7 path | **own J-PAKE client** — we owned the crypto session and the connection | **D2W piggyback** — ride the Dexcom watch app; our client reads alongside | stock **G7SensorKit** riding the Dexcom session (trigger b: connection events; trigger c: our own scan) |
| Pod policy | held/lead-time arming ("scan is the primitive", 300−45 geometry) | E4: **orphan between doses**, reclaim per dose | E4 inherited, plus **connectOnDemand** (next-dev concept, no pure equivalent) |
| Radio posture | ONE G7 owner (us), pod acquisition scheduled around known G7 windows | two G7 links per window (Dexcom's + ours), pod churns | same as pure plus connectOnDemand's extra connects on every foregrounding |

**Why crude is a controlled experiment, and its limits.** Crude proves the pod side can work
when acquisition is *scheduled* (lead-time arming against the known G7 cadence) rather than
*reactive* (reclaim-on-demand). But its G7 half is a different world — one owner, own crypto, no
Dexcom app in the mix — so its radio economics don't transfer directly. Its lesson that DOES
transfer: **acquisition timed to known quiet windows beats acquisition on demand.**

**The E4 premise has rotted.** Orphan-between-doses was designed to keep the pod's link from
starving a G7 *we ourselves were driving*. On next-dev we don't drive the sensor radio — the
code says so — and the held-link evidence (1.2) says a standing pod link is cheap. Meanwhile
E4 generates ~12 acquisition attempts/hour, each one scanning, each one issuing intents, each
one a chance to feed the table. **The policy built to protect the G7 is now the main producer
of the traffic that locks the G7 out.** [HYP for the causal link — the intent ledger is the
test — but every component of it is individually [MEAS].] **JB okay got it, but i think "chance to feed the table" is soemting to explore further**

> **Answered.** Worth exploring, but the phrase has to be retired: "chance to feed the table" assumed
> the table fills from our leaked intents, and 4.1 killed that. What survives is narrower and still
> real — **each acquisition is a chance for two of our own connect paths to collide**, which is a race,
> not an accumulation. The distinction matters for the fix: a race is fixed by mutual exclusion (done),
> an accumulation would be fixed by hygiene (item 2, now downgraded).

---

# Part 4 — RESOLVED: the anatomy of a Code=11, measured

> **SUPERSEDED IN PART, 2026-08-19 15:15.** Everything in Part 4 is about CONNECTING, and connecting
> turns out not to be where reclaims fail. Every FAILED ladder in e132 issued **zero** connect
> attempts — the pod never advertised — while the Code=11 refusals happened inside ladders that
> SUCCEEDED. Part 4 is still accurate about the refusal mechanism; it is simply about a minor failure.
> The dominant one is DISCOVERY. See the 15:15 entry in `POD_COMMS_FIELD_2026-08-18.md`.

**Everything below Part 4 was rewritten on 2026-08-19 after the connect-intent ledger reported from
the field. Two hypotheses I argued hard for are dead. Read this before the older reasoning.**

## 4.0 The ceiling is TWO, and it is documented — the number I had been treating as unknown

Jeremy's research (2026-08-19) settled the question I had left open:

- `CBErrorDomain Code=11` is `CBError.connectionLimitReached` — "the device already has the maximum
  number of connections." Unambiguous once the DOMAIN is included; bare "code 11" is meaningless,
  since HCI `0x09`, HCI `0x0B`, ATT `0x11` and `CBATTErrorDomain 11` are all different things.
- **Apple documents the watchOS third-party ceiling as two simultaneous connections** — WWDC17
  ("Limited to 2 simultaneous connections") and WWDC22 ("a limit of two Bluetooth connections for
  each app"). Nothing public raises it for watchOS 26 or the SE 3.
- What remains genuinely undocumented is the SE 3 controller's total capacity and how watchOS
  splits it between apps and system services. Per-app vs shared-across-third-party-apps is
  inconsistent in the public record (Apple says per app; WorkOutDoors reports two across all).

**The structural consequence, which was never written down before.** The watch extension embeds two
BLE stacks that hold connections — `G7SensorKit` and `OmnipodKit` — in ONE process, and the research's
own guidance is to assume every `CBCentralManager` in a process shares the quota. So:

| slot | holder |
|---|---|
| 1 | G7 sensor |
| 2 | pod |

**We designed a system that runs permanently at 100% of its connection budget with zero headroom.**
That is not a tuning problem. It is the shape of the thing.

Note also that the per-app-vs-shared ambiguity barely affects our own diagnosis — both our stacks are
in our process either way. What it decides is whether **D2W competes with us at all**. If Apple's
"two for each app" is right, it does not, and a good deal of the reasoning in Part 2 (and the standing
"never buy takeover reliability with G7 radio time" rule) is aimed at the wrong target.

## 4.1 The one Code=11 we have fully instrumented — and what it killed

Field 2026-08-19, loan e131, build with the connect-intent ledger. **One refusal in six issued
intents across the session.** [MEAS]

```
12:56:51.686  g7-ble didDisconnect DXCMqL              <- G7 releases, 2.3 s BEFORE
12:56:53.786  g7-ble scan-start: KNOWN peripheral state=0
12:56:53.974  [intent] connect via timedConnect  -> open=1 issued=5
12:56:53.974  [intent] connect via adopt-retry   -> open=1 issued=5   <- SAME MILLISECOND
12:56:53.982  [intent] refused
12:56:53.983  Pod failed to connect ... CBErrorDomain Code=11
12:56:54.733  [intent] connect via timedConnect  -> open=1 issued=6   <- single connect
12:56:55.996  [intent] resolved                                        <- SUCCEEDS, 0.75 s later
```

**Two hypotheses died here, both mine:**

1. **`recreateCentral`'s orphaned intent is NOT the leak.** `ORPHANED=1` was set at 12:53:29 and
   stood for the rest of the session — *including across connects that SUCCEEDED* at 12:53:31 and
   12:56:55. A standing orphan does not hold a slot. I had called this the prime suspect and
   proposed cancel-before-drop as the fix; this data says that fix would have changed nothing.
2. **The G7 was not holding the link.** It had disconnected 2.3 s before the refusal. So this
   refusal is not G7 contention either — which is how the 2026-08-18 headline read it.

**What is left, and cannot be separated at n=1:**

- **(A) Our own duplicate connect.** Two paths issued `connect()` for the same peripheral in the same
  millisecond. The research's engineering guidance names this explicitly ("never issue duplicate
  connect calls for the same peripheral"). G7SensorKit already learned this as the #101 churn fix
  (`G7BluetoothManager.handleDiscoveredPeripheral` returns early on `.connecting`); the pod path
  never got the equivalent.
- **(B) watchOS releasing a slot lazily.** The G7 disconnected 2.3 s before the refusal and the retry
  succeeded 3.0 s after it. WorkOutDoors reports exactly this — watchOS being slow to release a
  connection, so the next attempt hits the limit transiently.

**UPDATE 2026-08-19, loan e132 — (A) confirmed at n=2, and (B) weakened.** A second refusal, still on
pre-fix code, carried the identical `timedConnect` + `adopt-retry` same-millisecond signature — but
this time the G7 was CONNECTED (not released 2.3 s earlier) and ORPHANED was **0** for the whole
session. G7 state differs, orphan count differs, the duplicate is present in both. See
`POD_COMMS_FIELD_2026-08-18.md` for the comparison table.

The retry succeeding 0.75 s later fits both. **(A) is ours, cheap, and correct under either theory**,
so it is the fix that went in (2026-08-19): `noteConnectIssued` now returns a verdict and callers skip
the `connect()` when one is already in flight. Suppressions are COUNTED (`suppressed=N` in the ledger
line), so if that number climbs while reclaims still fail, (A) was not the disease and (B) is next.

Deliberately NOT guarded: connecting an already-`.connected` peripheral, which makes CoreBluetooth
re-deliver `didConnect` immediately. Some state machine may lean on that, and this file compiles into
the PHONE as well as the watch — suppressing it would risk wedging the phone's pod link to fix a
watch symptom.

## 4.2 The observability trap that distorted the whole session: `appInstalled=false`

Not BLE, but it is the phone↔watch link and it invalidated most of the run, so it belongs here. [MEAS]

The hand-back at 13:01:49 **succeeded** — phone committed, took ownership, and verified a live pod
round-trip in **one second** (the fastest settle in any log we hold). Yet the watch sat spinning on
"returning records" until it died, and the phone re-ACKed every 15 s for twenty minutes:

```
[wc] send handbackAck path=queued bytes=97 (interactive=true reachable=false)
[link] watch reachable=false activation=2 paired=true appInstalled=false
```

19 acks queued against 14 delivered live. `WCSession.isWatchAppInstalled` was **false**, so WCSession
refused live delivery and queued everything; the watch never got the ack, so it never left the
returning state, so it re-offered — forever.

`appInstalled` flapped all day in lockstep with the install churn: true 12:31–12:36, false 12:40:33,
true 12:47–12:49, false from 12:50:47 onward, and false for the whole 10:21–12:08 stretch.

**Two consequences.**

- **A direct Xcode/devicectl install to the watch can leave the phone's companion registration wrong,
  and the loan protocol's ack path depends on that registration.** Local installs are therefore not a
  clean test bed for hand-back until `appInstalled=true` is confirmed on the phone side.
- **The watch will spin on "returning records" indefinitely when the phone already owns the pod.**
  There is no ceiling on that path. It is a real defect independent of the install issue: the watch
  should give up and say the phone has it. Nothing is at risk when it happens — the pod is home — but
  it looks exactly like the state where something IS at risk.

## 4.3 The old claim list, scored against the measurement

The five claims this document made before the ledger reported, and what became of each:

| # | claim | verdict |
|---|---|---|
| 1 | Steady-state coexistence is fine — held pod link + G7 window, 263 cycles | **STANDS** |
| 2 | The scarce resource is the connection table, not airtime | **STANDS**, and now has a documented number: two |
| 3 | The table fills because acquisition churn leaks pending intents (`recreateCentral`) | **DEAD.** ORPHANED=1 stood across successful connects |
| 4 | Failed acquisition is also a UI outage (28 s ladder holds the glance's queue) | **STANDS**, unaddressed |
| 5 | Table size / per-app accounting / reclaim-on-death unknown | **PARTLY ANSWERED** — size is 2, accounting still ambiguous |

Claim 3 was the one the whole instrumentation push was built to test, and it failed the test. That is
the ledger working as designed: it was written to be able to kill its own hypothesis, and it did.

**On claim 1 (Jeremy's question — "does this change if we're using mode b?"):** unknown, and the
question is sharper than it looks. The 263-cycle census was taken with a HELD pod link. Trigger (b)
— connection events — changes when *our* connects happen, not how many slots exist, so the ceiling is
the same. What changes is the odds of two connects overlapping, which is exactly the thing that just
bit us. Not measured under (b). [UNK]

## 4.4 What the older confounders are worth now

Both were written before the ledger reported. Neither is overturned; both are demoted.


### 4.4a BATTERY. The "it accumulates within a session" evidence is confounded.

Battery level per session, from the logs' own `pwr` field:

| session | battery | reclaim outcome |
|---|---|---|
| 08-18 08:32–10:06 | **95%** | pod reconnect failures at 09:25, 09:33 |
| 08-18 10:55–13:42 | 75–85% | — |
| 08-18 14:29–16:31 | 65–70% | reclaim reads failing at 16:27 |
| 08-18 17:31–22:32 | 55% → **30%** | L2–L7 failed; **L8, L9 succeeded** at 22:31 |
| 08-19 07:26–08:47 | **10% → 5%** | 9/9 failed; Code=11 on pod **and G7**; 20 min dead |

**The problem for my leak hypothesis: "gets worse across a session" and "battery drains across a
session" are the same curve.** I cited the within-session degradation as evidence for accumulating
orphaned intents. It is equally consistent with watchOS tightening radio behaviour as the battery
falls — and at 5–10% the watch is at or below the Low Power Mode threshold, where BLE background
work is throttled by policy.

What the table does NOT support is battery as a *sufficient* explanation: reclaims failed at 95%,
and two succeeded at ~30%. So battery is not the disease either. But the worst episode by far —
both stacks locked out, twenty minutes dead — is also the lowest-battery episode by far, and I
should not have written "accumulates" without noticing that.

**[UNK] and worth asking Jeremy:** was Low Power Mode on during the 08-19 session? watchOS
prompts at 10%. If it was, that session is not comparable to the others at all.


**JB okay, I'm structrually skeptical of battery explanations. I find it plausible that low power mode changes behavior.  I find it plausible that even with low power mode off, at the lowest levels of battery, some behavrior changes.  I don't find it plausible that between 85 and 65%, behavior changes.  We should instrument whether low power mode is on.  **

> **Answered, and you are right — I am withdrawing the battery claim, not defending it.** Re-reading my
> own table, it never showed a monotonic effect; it showed early-session success and late-session
> failure, with battery as a passenger. 85% → 65% changing radio behaviour is not plausible and I
> should not have written it as a confounder worth ranking. Low Power Mode is plausible and is
> UNINSTRUMENTED, which is the actual gap — Part 5 item 7. Until that ships, battery percentage should
> not appear in any argument in this document.

**Consequence for the intent ledger:** it still discriminates. If ORPHANED climbs at 95% battery
in a session where reclaims fail, the leak is real and battery-independent. If ORPHANED stays
flat and failures track battery only, the leak theory dies. Record the battery with every field
session from now on — it is already in the log, we simply were not reading it.

### 4.4b The watch-app INSTALL is probably competing with our own radio use

Jeremy's three observations (2026-08-19): (1) the app finished installing on the watch **while
the phone's Watch app was still spinning**; (2) after deleting, an install took forever; (3)
build 113 that morning was fast.

**(1) says the spinner is not a truth source** — the install completed and the progress UI did
not know. That reframes most "the install is broken" reports as "the progress UI is unreliable",
which is the same display-vs-truth divergence pattern this project keeps finding elsewhere.

**Theory for (2) vs (3) [HYP].** A watch app arrives by the phone transferring the payload over
the peer-to-peer link. That transfer is dramatically faster over peer-to-peer Wi-Fi than over
Bluetooth, and it shares the watch's single radio with **our G7 scan and our pod centrals**. So:

- After a delete, the whole bundle transfers rather than a delta — more bytes over a contended
  link.
- While Sport Mode is running, we hold a near-continuous G7 scan (2.1a) plus pod acquisition
  traffic, which is precisely the load that would starve the transfer.

**The test is cheap and decisive: force-quit the Sport Mode app on the watch before installing.**
If installs become reliably fast, our own radio behaviour is starving the channel that updates
us — which would be a satisfying irony and an argument for the scan-geometry work in its own
right. Prediction stated in advance so it can fail.

**JB okay this is interesting, but in general, I hvaen't been installing while also trying to run sport mode, so i'm confused about this** 

> **Answered — this section is now mostly WRONG and is kept only for the record.** Jeremy: he has not
> been installing while running Sport Mode, which removes the premise. And 4.2 supplies the real
> mechanism: installs disturb `WCSession.isWatchAppInstalled`, which breaks the phone↔watch ACK path.
> The install interferes with the **companion registration**, not with the BLE radio. Same symptom
> (things stop working around installs), completely different cause, and the radio-contention story
> sent us looking in the wrong layer.

**Dead theory, recorded so it is not retried:** I suggested the pinned `CURRENT_PROJECT_VERSION`
(58) might make watchOS refuse a same-version replacement. **Wrong.** TestFlight builds carry
ASC-assigned numbers (109, 111, 112, 113 all observed on the wrist) and `install-pair` assigns its
own incrementing dev series (1001–1008 observed). Both paths produce distinct build numbers, so
there is no collision to refuse.

---

# Part 5 — What to do next (rewritten 2026-08-19, after the ledger reported)

**Jeremy's steer, taken:** *"I think you're giving me too much deference. We need to push through
with experiments to determine what is actually true about contention, tables, etc, and then code
accordingly."* This list is therefore ordered by what each item MEASURES, not by how appealing it is.

1. **DONE 2026-08-19 — kill the duplicate connect.** `noteConnectIssued` returns a verdict; callers
   skip `connect()` when one is already in flight. Counted as `suppressed=N`, so it reports on
   itself. Correct under both surviving theories (4.1). Guards `.connecting` only, never
   `.connected` — this file compiles into the phone too.

2. **NOT DONE, and now DOWNGRADED — intent hygiene (cancel before dropping a central).**
   Jeremy asked directly whether this was done: **no, only instrumented.** And the instrumentation is
   the reason not to rush it — ORPHANED=1 stood across successful connects, so the leak this was
   meant to plug does not exist. Do it as hygiene if the central rebuild survives at all (2.3), not
   as a fix.

3. **THE EXPERIMENT — does pod activity affect G7 acquisition?** Jeremy has authorised overruling his
   own rulings to find out ("we need to do that controlled experiment. Maybe we should add modes to
   the diagnostic screen"). Diagnostic modes are the right shape: pod-hold on/off, G7 trigger (a)/(b),
   toggled on the wrist, with the census reporting per mode. This is the item that converts standing
   rules from belief into measurement, and everything below is guesswork until it runs.
   **Precondition:** `appInstalled=true` on the phone (4.2), or the run is uninterpretable.

4. **Hold the pod link for the life of a loan** — one acquisition per loan instead of ~12/hour. Still
   the biggest single reduction in churn, and it removes the 28 s ladders and the frozen glance with
   it. But it is now a HYPOTHESIS ABOUT CHURN, not a fix for table exhaustion, because the table
   theory died. Sequence it after (3).

5. **Fix the "returning records" wedge** (4.2). Independent of all the above, no radio tradeoff, and
   it is the failure the user actually sees. The watch must give up when the phone owns the pod.

6. **G7 doorway re-ordering — connection events first, guard-band scan second, never continuous**
   (2.1a). Jeremy: *"let's not do this unless we have to. Maybe we'll have a much more elegant
   solution based on what we've learned."* Agreed, and the clock finding (2.1a) is what makes an
   elegant version possible: the grid is exact, so ONE reading anchors every future window and the
   only genuinely blind period is the first acquisition after launch. Park until (3) reports.

7. **Instrument Low Power Mode**, and stop invoking battery percentage until it is (4.4a).

8. **Re-verify the "outage"** against the D2W control before treating any G7 gap as a sensor fact.
   Low priority, per Jeremy.
