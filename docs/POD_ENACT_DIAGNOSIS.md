# The residual pod-connect failure — what we actually know

Status 2026-08-20. Supersedes the "we can't hear the pod" framing.

## The failure, in full

Watch log, 2026-08-19. G7 healthy (the 20-40 min outage was fixed the night before
and held 34/34 windows). Pod free and broadcasting — the Mac scanner heard it at
-56 dBm every 2-7 s throughout. And:

```
12:59:51.163  E4: reclaim starting L5 — pod BLE state disconnected, released=yes, idle 28s
12:59:51.165  [loan-scan] marker nil -> 0x177e6b7e (escalate)
12:59:51.181  [loan-takeover] scan started (filter=00004024-…)
              (14 reads, 2 s apart, every one "pod BLE state disconnected")
13:00:16.182  CYCLE VERDICT computed=ok enact=FAILED communication(nil)
13:00:19.383  L5 FAILED after 14 read(s) in 28.2s — never reconnected · still live: none
```

## What that trace establishes

**1. The scan was armed.** Logged, with its filter. So this is NOT the same bug as
the G7 outage (`activePeripheral == nil` leaving no scan armed during a pending
connect). Different failure, same family.

**2. No connect was ever issued.** The peripheral read `.disconnected` on all 14
reads. A connect in flight reads `.connecting`. In the takeover path the only thing
that issues a connect is adopt-on-discovery, and nothing adopted.

This kills the leading hypothesis from L10 (connect issued, then cancelled by one of
our nine cancel sites). There was no connect to cancel. A ladder that re-issues a
dead connect — proposed and dropped — would have done nothing here.

**3. Therefore the failure is upstream of the connect: 28.2 s of armed scanning
produced no adoptable advertisement**, against a pod that was demonstrably speaking
every few seconds.

## The one bit we still don't have

Two incompatible stories fit that trace equally well:

| | mechanism | fix direction |
|---|---|---|
| **Deaf** | the central received no didDiscover at all | radio/stack — restart the scan, or the watch's central is wedged |
| **Rejected** | frames arrived and every one failed a gate | filter, parse, or address match |

`adverts=0` cannot arbitrate, because it only counts frames that already passed the
address match. Both stories produce `adverts=0`.

### Why no instrument answered it

Three separate blindnesses, all now fixed:

- **The census didn't report raw discovery.** `anyDiscoveryCount` existed but was
  printed only in the periodic state line, never in the ladder's own failure line.
- **The scan watchdog could not fire inside a ladder.** It required 45 s of silence,
  checked every 20 s. The ladder lives 28.2 s. Earliest possible firing was ~17 s
  *after* the ladder gave up and tore the marker down. `scanWD=0` on the wrist never
  meant "no deafness" — it meant "never checked".
- **The census address match fell back to `autoConnectIDs`**, which
  `releaseConnection()` empties. So after every post-dose release the pod's frames
  stopped being *counted* whether or not they were *received*.

### What the next failing ladder will print

```
L5 FAILED after 14 read(s) in 28.2s — never reconnected · adverts=N anySeen=M skipped=K …
```

- `anySeen>0, adverts=0` → **rejected**. Frames arrived; the address match discarded
  them.
- `adverts>0, skipped>0` → heard and refused at the adopt gate (now dwell-qualified,
  so it only fires on a genuine wedge).
- `adverts>0, skipped=0, no connect` → a gate we haven't instrumented. New finding.

### Correction, same day: `anySeen=0` is NOT deafness

The first cut of this document read `anySeen=0` as "deaf". That was wrong, and the
11:08 build fixes it. **The takeover scan is filtered** — `scanForPeripherals(withServices:
[podScanServiceUUID], allowDuplicates: true)` — so the only thing that can raise
didDiscover at all is a pod. A deaf central and a pod whose frames never arrive or never
match therefore produce the *same* `anySeen=0`. A filtered scan cannot answer the
question from inside itself.

**The wildcard probe is the answer.** Every odd watchdog restart now re-arms with no
service filter, and `wildcard=heard/Ns` rides in the census:

- `wildcard=0/Ns` in a room with any BLE traffic → **deafness demonstrated**, not inferred.
- `wildcard=N>0` → the central is receiving. Deafness is off the table; the fault is in
  the frames, the filter, or the address match.

It is also a candidate fix: a wildcard scan is a strict superset of the filtered one, and
the adopt path matches the address out of the parsed advertisement rather than caring
which filter surfaced it. **If the service filter is wrong for this pod, the wildcard arm
adopts it and the takeover recovers.** The scan-arm line now also names which branch chose
the filter (`via O5/pdm-derived` vs `via profile(...)`), because a wrong branch scans
forever with no symptom but silence.

Plus, the watchdog now fires at 15-20 s **inside** the 28.2 s ladder rather than 17 s
after it ends, leaving 8-13 s for a restarted scan to recover.

## Where the deferred items sit

| item | in this build? | relation to this failure |
|---|---|---|
| freshConnect enforcement | **yes** | none causally. It was a *lying instrument* — logged REFUSED, connected anyway — which corrupted our reading of whether the phone was contending. |
| census fallback | **yes** | direct. It is why `adverts=0 last=never` was unusable as evidence for two nights. |
| stuck-`.connecting` handling | detector only | **not this bug.** The peripheral was `.disconnected`, not wedged. The dwell-qualified adopt gate will say `WEDGED` if it ever is; only then is the handling worth building. |
| grant-gate replacement | no | unrelated — that is the phone refusing a Start tap. Own build, needs a design. |
| glance off the queue | no | unrelated — UI responsiveness. Own build. |

## What to read off the next failing loan

One line, in this order:

1. `[loan-takeover] scan started (filter=… via …)` — is the filter branch right?
2. `[scan-watchdog] … filter=WILDCARD probe` — did the watchdog fire at all inside the ladder?
3. `L<n> FAILED … adverts=A anySeen=S skipped=K wildcard=W/Ts` — the verdict.

If the ladder now SUCCEEDS on a wildcard restart, the service filter was the bug.

## Honest residual

We do not know the mechanism. We know its *location* (discovery, not connect), we
know four instruments that were lying about it, and the next failing ladder resolves
it to one of three named causes on a single line. That is a materially different
position from "the pod won't connect and we don't know why", but it is not a fix.
