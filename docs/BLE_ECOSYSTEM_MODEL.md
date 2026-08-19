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

**[Jeremy/ground-truth]** The sensor accepts up to **three** collectors. On the watch during a
window, plausibly two of those are in play: the Dexcom watch app's own link and ours (the
"piggyback"). Whether the sensor serves collectors simultaneously or sequentially within one
window: [UNK], and it matters for worst-case window timing.

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

## 2.3 The watch

One BLE radio time-sliced among: the phone link, AirPods (Classic — heavy when streaming), the
system's own Dexcom bond, the Dexcom watch app's G7 link, **our G7 central**, and **our pod
central(s)** — plural, because `escalateLoanReclaim` recreates the pod central by design. Every
one of these except AirPods draws on the same LE connection table.

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
test — but every component of it is individually [MEAS].]

---

# Part 4 — The contention model, stated as claims

1. **[MEAS]** Steady-state coexistence is fine: held pod link + G7 window worked for 263 cycles.
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

# Part 5 — What the model implies for the next phase (proposals, not decisions)

1. **Hold the pod link for the life of a loan.** One acquisition per loan instead of ~12/hour.
   Cheap while held (1.2), removes the churn that feeds the table, removes the 28 s ladders,
   removes the frozen glance. Touches R31 and "G7 connectivity outranks takeover" — Jeremy's
   call, and the intent-ledger data should arrive first.
2. **Intent hygiene regardless:** cancel every pending connect before dropping a central;
   audit connectOnDemand's fallback the same way. Correct under any theory.
3. **If acquisition must stay reactive anywhere, schedule it** in the G7's quiet 4½ minutes —
   crude's transferable lesson — rather than colliding with windows blindly.
4. **Re-verify the "outage"** with the new instrumentation AND the D2W control before treating
   any G7 gap as a sensor fact.
