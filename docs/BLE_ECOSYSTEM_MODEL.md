# The BLE ecosystem — what is physically true, what we designed, what we know

**Status: DRAFT for Jeremy's markup, 2026-08-19.** The step-back document: one model of the
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

**Important caveat, or this becomes the fourth wrong theory:** shrinking the G7 scan is a real
win in receiver time and coexistence pressure, but it probably does **not** touch the Code=11
disease. Code=11 is a *connection-table* error and **a scan holds no table entry**. If we fixed
only the scan and left the intent churn alone, the expectation is that the lockups continue.
Scan geometry and intent hygiene are separate problems that happen to share a symptom. *JB understood.  Let me read to the end, but I have some questions about Code = 11*

**[Jeremy/ground-truth]** The sensor accepts up to **three** collectors. On the watch during a
window, plausibly two of those are in play: the Dexcom watch app's own link and ours (the
"piggyback"). Whether the sensor serves collectors simultaneously or sequentially within one
window: [UNK], and it matters for worst-case window timing. **JB good point about that.  I could probably do an experiment by staring at the D2W app in the watch and noting when it updates.  Important to note - the statement of 2 connectors is true when the phone is off.  WHen it's on, we're using all 3 - phone, D2W, Sport mode.  I think, I'm not sure*

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

## 2.3 The watch

One BLE radio time-sliced among: the phone link, AirPods (Classic — heavy when streaming), the
system's own Dexcom bond, the Dexcom watch app's G7 link, **our G7 central**, **JB wait, this feels like too mnay.  What's "the systems onwn decome bond as opposed to teh decom watch's app G7 link"? and what is the difference betwene "our G7 central" as opposed to sport mode's G7 connection.  Maybe its' the same ** and **our pod
central(s)** — plural, because `escalateLoanReclaim` recreates the pod central by design. Every
one of these except AirPods draws on the same LE connection table.  **JB I sknow you're implicitly already suggesting this, but having multiple pod centrals seems bad and possibly unnecessary.  We hsouold understand this better.**

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

---

# Part 4 — The contention model, stated as claims

1. **[MEAS]** Steady-state coexistence is fine: held pod link + G7 window worked for 263 cycles.  **JB okay, but do we know how thsi changes if we're using mode b**
2. **[MEAS]** The scarce resource is the connection table, not airtime: Code=11 hits both
   stacks at once and a table reset fixes both at once.
3. **[HYP → instrumented]** The table fills because acquisition churn leaks pending intents —
   `recreateCentral` drops centrals that have open connects, `connectOnDemand` adds more, and
   nothing cancels them. The ledger's ORPHANED counter is the direct test. Corroborating
   precedent: the old field note "G7 pending connect eats a BLE slot; takeover CBErrorDomain#11
   is OURS" — same error, same mechanism family, seen from the other side.
4. **[MEAS]** Failed acquisition is also a UI outage: a 28 s ladder holds the loan controller's
   serial queue, which the glance ticks on.
5. **[UNK]** The actual table size, per-app vs per-device accounting, and whether watchOS
   reclaims abandoned intents on client death. These decide how aggressive the fix must be.

---

# Part 4 — Two confounders found while writing this, both weakening claims above

## 4.1 BATTERY. The "it accumulates within a session" evidence is confounded.

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

**Consequence for the intent ledger:** it still discriminates. If ORPHANED climbs at 95% battery
in a session where reclaims fail, the leak is real and battery-independent. If ORPHANED stays
flat and failures track battery only, the leak theory dies. Record the battery with every field
session from now on — it is already in the log, we simply were not reading it.

## 4.2 The watch-app INSTALL is probably competing with our own radio use

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

**Dead theory, recorded so it is not retried:** I suggested the pinned `CURRENT_PROJECT_VERSION`
(58) might make watchOS refuse a same-version replacement. **Wrong.** TestFlight builds carry
ASC-assigned numbers (109, 111, 112, 113 all observed on the wrist) and `install-pair` assigns its
own incrementing dev series (1001–1008 observed). Both paths produce distinct build numbers, so
there is no collision to refuse.

---

# Part 5 — What the model implies for the next phase (proposals, not decisions)

1. **Hold the pod link for the life of a loan.** One acquisition per loan instead of ~12/hour.
   Cheap while held (1.2), removes the churn that feeds the table, removes the 28 s ladders,
   removes the frozen glance. Touches R31 and "G7 connectivity outranks takeover" — Jeremy's
   call, and the intent-ledger data should arrive first.  **JB I'm okay overruling my rulings here to test the hypothesis that G7 connection is unaffected by pod status.  We need to do that controlled experiment.  Maybe we should add modes to the diagnostic screen.  **
2. **Intent hygiene regardless:** cancel every pending connect before dropping a central;
   audit connectOnDemand's fallback the same way. Correct under any theory. **JB okay did we do this already or no?**
3. **If acquisition must stay reactive anywhere, schedule it** in the G7's quiet 4½ minutes —
   crude's transferable lesson — rather than colliding with windows blindly. **JB yes, no blind collision.  But let's not do this unless we have to. Maybe we'll have a much more elegant solution based on what we've learned** 
4. **Re-order the G7's doorways: connection events, then a guard-band scan, never continuous**
   (2.1a). Frees ~3½ minutes of receiver time per cycle for pod acquisition. Ranked BELOW 1 and 2
   deliberately: it addresses airtime, and the measured disease is table exhaustion. Worth doing
   on its own merits; not to be mistaken for the cure. **JB yeah, I think you're giving me too much deference here.  I think we need to push through with experiements to determine what is actually true aboht contention, tables, etc, and then code accoridngly.  We're close.** 
5. **Re-verify the "outage"** with the new instrumentation AND the D2W control before treating
   any G7 gap as a sensor fact.  **JB.  Sure.  Low priority**.
