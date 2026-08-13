# Measurement error budget — gravimetric micro-leak detection

**Objective:** resolve a leak rate of 0.01 mL/min, i.e. **10 mg/min** of water
captured.

All figures below are derived from the datasheets and quotations held in this
repository. Where a number is an estimate rather than a vendor specification it
is marked as such and carries the assumption it rests on.

---

## 1. The signal

Leak rate is estimated as the **slope of captured mass against time** over the
pressurised hold, not as the difference between two readings.

That choice matters more than any hardware decision. A slope fit is blind to
any constant offset — load cell zero balance, tare error, the mass of the catch
vessel, absolute calibration error. What survives is only what *changes during
the hold*.

So the accuracy specification on the load cell (typically ±0.03 % to ±0.05 % of
rated capacity) is **not** the relevant figure of merit. Drift, creep and
evaporation over the hold window are.

Total signal available:

| Hold duration | Captured mass at 10 mg/min |
|---|---|
| 10 min | 100 mg |
| 20 min | 200 mg |
| 60 min | 600 mg |

Signal grows linearly with hold time; random noise averages down. Hold duration
is the single cheapest lever available, and it costs nothing but test time.

---

## 2. Error sources, ranked

Reference case: **20-minute hold, 200 mg of signal.**

| # | Source | Magnitude over 20 min | Share of signal | Nature |
|---|---|---|---|---|
| 1 | Evaporation, open vessel Ø80 mm | 80–170 mg *(est.)* | 40–85 % | Bias, **negative** |
| 2 | Cell zero drift — 1 kg cell, 1 °C swing | 50 mg | 25 % | Drift, either sign |
| 3 | Creep, load not pre-settled | ~50 mg | 25 % | Bias, positive-decaying |
| 4 | Quantisation if raw value truncated to 16-bit `INT` | 30 mg | 15 % | Resolution floor |
| 5 | Cell zero drift — 250 g cell, 1 °C swing | 12.5 mg | 6 % | Drift, either sign |
| 6 | Creep, load pre-settled before hold begins | <1 mg | <0.5 % | Negligible |
| 7 | Quantisation, 24-bit read as `DINT` | 0.15 mg | negligible | Negligible |

### 2.1 Evaporation — the dominant term, and the dangerous one

An uncovered catch vessel loses water continuously. Using a still-air
evaporation rate of 0.05–0.10 kg/(m²·h) at ~20 °C and ~50 % RH, and an assumed
80 mm diameter opening (0.005 m²):

```
0.05 kg/(m²·h) × 0.005 m² = 250 mg/h ≈ 4 mg/min
0.10 kg/(m²·h) × 0.005 m² = 500 mg/h ≈ 8 mg/min
```

**That is 40–85 % of the leak rate being measured**, and it acts in the negative
direction — it removes mass. A valve leaking at exactly the acceptance
threshold would measure well below it and **pass**. This is a
fail-to-danger mode, not merely an accuracy problem.

The estimate is coarse; the rate depends strongly on air movement over the
surface, and a draught from a cabinet fan can double it. But it does not need
to be precise to force the conclusion:

> **The catch vessel must be sealed.** A lid with a close-fitting port for the
> drain tube, not an open beaker.

A sealed vessel also removes the risk of splash, and of the operator's presence
altering the airflow between tests.

Regardless of sealing, the rig should run a **blank test** — full procedure,
pressurised, on a known-tight valve or a blanked port — to measure whatever
residual drift the whole system exhibits with zero leak. That blank rate is the
true noise floor and should be subtracted or, better, used as the acceptance
sanity check.

### 2.2 Load cell zero drift with temperature

This is the term that scales with rated capacity, and the reason capacity
selection matters.

| Cell | Spec | Absolute zero drift |
|---|---|---|
| Novatech F238, 1 kg (quoted QU-24976) | ±0.005 %RL/°C | **±50 mg/°C** |
| Applied Measurements OBUG, 250 g | <0.005 %RC/°C | **±12.5 mg/°C** |
| Applied Measurements OBUG, 1 kg | <0.005 %RC/°C | ±50 mg/°C |

To hold this term to ≤10 % of a 200 mg signal (≤20 mg):

- **1 kg cell** → temperature must be stable to **±0.4 °C** across the hold.
- **250 g cell** → **±1.6 °C** is sufficient.

±0.4 °C across 20 minutes is not achievable in an uncontrolled workshop next to
a hydraulic power pack. ±1.6 °C usually is.

This is the concrete argument for the smallest capacity the mechanical design
permits — not resolution, which is a non-issue, but **thermal drift referred to
full scale**.

Longer holds do not help this term, because drift is not random: it tracks
ambient temperature, which typically moves monotonically over tens of minutes.
Only reducing capacity, or stabilising temperature, helps.

### 2.3 Creep

Creep is a slow monotonic settling of the sensing element under sustained load.
It is the most treacherous error in this application because it **looks exactly
like a leak**: a smooth, monotonic mass increase under constant conditions.

| Cell | Spec | Reference |
|---|---|---|
| Novatech F238 | ±0.05 % over 20 min | **applied load** |
| Applied Measurements OBUG (≤2 kg) | <0.08 % over 30 min | **rated capacity** *(to confirm)* |

The reference basis matters enormously:

- F238's creep is proportional to **applied load**. With a ~100 g vessel that is
  ±50 mg over 20 min — significant if the load is applied at the start of the
  hold, but the creep from the *accumulating leak mass itself* is only
  0.05 % of 200 mg = **0.1 mg**, i.e. nothing.
- The OBUG datasheet states creep against **rated capacity**, which for a 250 g
  cell would be 200 mg over 30 min *regardless of load* — worse than the F238
  in this application despite the better drift spec. Manufacturers sometimes
  write %RC where they mean %RO at applied load; **this should be confirmed
  with Applied Measurements before ordering.**

The mitigation is procedural and free:

> Place the catch vessel on the cell and let it settle for **several minutes**
> before the hold begins, then tare. Creep decays roughly logarithmically, so
> most of it is spent before measurement starts, and the residual creep from
> the small accumulating leak mass is negligible.

The existing draft code uses a 3-second settle time. Three seconds handles
mechanical swing of the suspension. It does not touch creep. This should be
minutes, and the tare must be taken at the **end** of the settle period.

### 2.4 Resolution — a non-issue in hardware, a real issue in software

The Beckhoff ELM3148 is a 24-bit, ±20 mA input. Mapping the 4–20 mA span onto
0–1000 g:

```
16 mA of a 40 mA range × 2^24 counts ≈ 6.71 × 10^6 counts across 0–1000 g
→ ≈ 0.15 mg per count
```

A 10 mg/min leak advances ~67 counts per minute. Quantisation is irrelevant.

**However**, the draft CODESYS program declares the raw input as a 16-bit `INT`
and scales `0…32767` onto 0–1000 g:

```
1000 g / 32767 ≈ 30.5 mg per count
```

At that resolution a full 20-minute, 200 mg signal is **6.5 counts**. The
24-bit hardware is being discarded by the variable declaration. The ELM3148
presents its value in a 32-bit process data object; the input must be declared
`DINT`, and the raw endpoints taken from the actual ESI / process-image scaling
rather than assumed.

### 2.5 Random noise

The Novatech SGA/D amplifier offers switch-selected low-pass filtering from
1 Hz to 5 kHz. Set it to **1 Hz** — there is no bandwidth requirement here; the
process being measured has a time constant of minutes.

Sampling at 1 Hz over a 20-minute window gives ~1200 points into the regression.
Zero-mean noise is suppressed by roughly √1200 ≈ 35×. Random noise is not the
limiting term and does not need further attention.

### 2.6 Two traps in the draft logic

**The negative clamp manufactures leaks.** The draft contains:

```
IF rActiveLeakMass < 0.0 THEN
    rActiveLeakMass := 0.0;
END_IF
```

Applied to a signal with zero-mean noise, this is a rectifier. It discards every
negative excursion and keeps every positive one, producing a positive bias — an
apparent leak on a perfectly tight valve. It also hides exactly the symptom that
would reveal an evaporation problem, which shows up as *negative* accumulated
mass. It must be removed; a slope fit needs no such protection.

**Instantaneous delta is not a rate.** The draft reports
`rAbsoluteMass - rTareMass` and labels it the leak volume. That is accumulated
mass at one instant, and it inherits every offset error in the chain. Acceptance
criteria under ISO 5208 and API 6D are expressed as **rates**, so a rate is what
the system must compute and log.

### 2.7 Mechanical coupling through the drain tube

Not a sensor specification, but capable of swamping everything above:

- The drain tube must **discharge above the free surface**, never dip into the
  collected fluid. A submerged tube couples surface tension and buoyancy into
  the measurement, and both change as the level rises.
- The tube must not rest on, or pull against, the vessel. Route it so its weight
  and stiffness are carried by the frame, with a slack loop before the vessel.
- Any condensation running down the outside of the tube into the vessel is
  indistinguishable from a leak.

---

## 3. Recommended configuration

In order of impact per pound spent:

1. **Seal the catch vessel.** Free. Removes the largest and most dangerous term.
2. **Extend the hold as far as the test procedure allows.** Free. Signal scales
   linearly with it.
3. **Pre-settle the load for several minutes and tare at the end of that
   period.** Free. Removes creep.
4. **Declare the raw input as `DINT` and take scaling endpoints from the ESI.**
   Free. Recovers a factor of ~200 in resolution.
5. **Remove the negative clamp; fit a slope instead of differencing.** Free.
   Removes a positive bias and gives a result in the units the standard uses.
6. **Buy the smallest rated capacity the mechanical design allows.** Costs a
   design constraint on catch volume, not money — the 250 g options are not
   cheaper than the 1 kg ones. This is the only remaining lever on thermal
   drift.
7. **Log catch-vessel temperature alongside mass.** A cheap Pt100 on the same
   terminal makes zero-drift a correctable term rather than an unknown one, and
   turns an argument about accuracy into a measurement.

Items 1–5 cost nothing and together move the budget from *not viable* to
*viable*. They should be settled before any purchase order.

---

## 3a. The confirmed configuration, and what it costs

Answers now fixed: **catch mass 250 g–1 kg** (so a 1 kg cell), **open workshop,
uncontrolled temperature**, **hold varies by valve size and spec**.

That combination puts thermal zero drift in charge of the whole design. With
all five free fixes applied and a 2 °C excursion across the hold:

| Hold | Signal | Drift error | Share |
|---|---|---|---|
| 10 min | 100 mg | 100 mg | **100 %** |
| 20 min | 200 mg | 100 mg | **50 %** |
| 30 min | 300 mg | 100 mg | **33 %** |
| 60 min | 600 mg | 100 mg | 17 % |

Drift is a **fixed mass error accumulated over the hold**. It does not grow
with time, so as a *rate* error it divides by the hold duration. Everything
follows from that:

### The hold a valve needs is derivable, not scheduled

```
T_min = k × TotalDrift_mg / (Threshold_mL_min × density × 1000)
```

with `k = 1/error_allowance` (5 for 20 %). Uncorrected, at 100 mg of drift:

| Threshold | Required hold |
|---|---|
| 0.01 mL/min | **50 min** |
| 0.02 mL/min | 25 min |
| 0.05 mL/min | 10 min |
| 0.10 mL/min | 5 min |

Because the ISO 5208 limit scales with nominal bore, **a small-bore valve on a
tight rate class needs a longer hold than a large one** — the reverse of what
test schedules normally assume. This is implemented in `F_MinHoldMinutes` and
enforced as a hard gate: a hold too short to resolve its own threshold cannot
return a pass, however clean the fit looks.

### The temperature channel pays for itself immediately

A Pt100 on the catch vessel, logged and used to correct the zero, is the
cheapest channel on the rack. If it removes 80 % of the drift (20 mg residual):

| Threshold | Uncorrected | Corrected |
|---|---|---|
| 0.01 mL/min | 50 min | **10 min** |
| 0.02 mL/min | 25 min | 5 min |

Fifty-minute holds on every small-bore valve is a throughput problem that will
get the rig abandoned. Ten is tolerable. **This is why `bTempChannelPresent`
defaults TRUE and the correction is not optional** in an uncontrolled
workshop — it is what makes the 1 kg cell viable at all.

The correction coefficient must come from the Stage 4.5 measurement of the
assembled chain, not the cell datasheet. Confirm the **sign** empirically: get
it backwards and the error doubles rather than cancelling, and the result still
looks entirely plausible.

### Channel B is a flowmeter — a caution

Independent physics is exactly what corroboration needs; the flowmeter does not
share the gravimetric channel's drift or vibration terms. But it brings its
own: **at 0.01 mL/min most flowmeters are at or below their stated minimum
flow**, where they read low, read nonlinearly, or stall completely. A flowmeter
agreeing with "no leak" may simply be below its threshold.

Treat channel B as corroboration only, never as the primary, and establish its
behaviour at the bottom of the range in Stage 5.5 before trusting any
cross-check. Specify minimum measurable flow, not just accuracy, when
purchasing.

---

## 4. Open questions blocking final selection

1. **Maximum captured mass per test.** Sets the required rated capacity, and so
   sets the thermal drift term. If the vessel can be sized or emptied to stay
   under ~250 g, drift improves 4× at no cost.
2. **Pressurised hold duration in the governing procedure.** Sets the available
   signal.
3. **Is the catch vessel in a temperature-controlled enclosure or ambient?**
   Determines whether the 1 kg option is usable at all.
