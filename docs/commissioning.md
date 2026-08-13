# Commissioning and qualification — Hydro Leak Detection

Rebuild → Requalify → Repeat, following the Temperature Cabinet Setpoint
Control methodology.

Every stage has a pass criterion. A stage is not complete until its criterion is
met and a dated log exists in `docs/test-logs/`. Drift found in later production
use re-enters at Stage 4.

**End objective:** resolve a leak of **0.01 mL/min ≈ 10 mg/min** of water, and
pass or fail a valve against its ISO 5208 rate class with evidence.

---

## Stage 1 — Hardware rebuild (electrical)

| Step | Action | Pass criterion |
|---|---|---|
| 1.1 | De-energise panel, apply LOTO. Confirm load cell, conditioner, 4-pin XLR cable and a free ELM3148 channel pair. | Visual + LOTO tag |
| 1.2 | **Pin-map the 4-pin XLR before connecting anything.** See below. | Documented pinout; two isolated pairs confirmed |
| 1.3 | Mount cell in the catch vessel bracket, isolated from the rig frame with rubber/silicone bushings. | No metal-to-metal path to the frame |
| 1.4 | Wire cell → conditioner: excitation + signal (6-wire if remote sense used). Torque per RDP/Novatech manual. | Excitation present at cell, no load |
| 1.5 | Set conditioner to 4–20 mA, 2-wire loop. TX20: `-AN` block, unipolar. DR7DC: confirm current-mode jumper, not voltage. **Set the low-pass filter to its lowest setting (1 Hz on the SGA/D).** | Loop reads ≈4.00 mA at zero load |
| 1.6 | Land loop 1 on the mapped XLR pins. Route via the DLS002 junction box — claim the SPARE port, or physically relabel an unused PT port. | Continuity panel → junction box |
| 1.7 | Land the pair on one ELM3148 channel per its **current-mode differential** terminal diagram — not the shared 0 V rail used by voltage channels. | Loop powers, no fault LED |
| 1.8 | **Seal the catch vessel.** Lid with a close-fitting port for the drain tube. | No open water surface |
| 1.9 | Land loop 2 (flowmeter) on ELM3148 channel B. Mount the catch-vessel temperature sensor **on the vessel body**, not in free air. | Both channels read, no fault LED |
| 1.10 | Route the drain tube so it **discharges above the free surface**, never dipping in, and so its weight and stiffness are carried by the frame with a slack loop before the vessel. | Tube exerts no force on the vessel at any fill level |

### 1.2 — The 4-pin XLR

Two positives and two negatives in one shell is **two independent 2-wire
4–20 mA loops**, not redundant wiring on one loop:

| Pin pair | Assignment |
|---|---|
| Loop 1 (+/−) | Primary load cell → conditioner → ELM3148 **channel A** |
| Loop 2 (+/−) | Flowmeter → ELM3148 **channel B** (corroboration) |

The connector was therefore already provisioned for the second channel that
rejects the two error terms a single gravimetric channel cannot distinguish
from a leak — thermal drift and vibration appear on the primary and on a
reference cell, but not on a flowmeter.

**Which physical pin number is which is not documented in this repo, the Temp
Cab repo, or any supplied PDF.** Establish it by continuity check, unpowered:

1. Ring out each pin to the cell/conditioner end. Record pin → function.
2. Confirm **no** pin-to-shell short.
3. **Confirm the two pairs are isolated from each other.** If they share a
   common return it is one loop plus a shared negative, not two loops, and the
   ELM3148 differential inputs must be wired differently. This is the one
   result that can invalidate the dual-channel design — check it first.

Record the result in `docs/test-logs/` and update the header of
`src/GVLs/GVL_IO.gvl`.

### 1.8 — Why sealing is a Stage 1 item, not a nicety

An open Ø80 mm vessel loses 4–8 mg/min to evaporation — 40–85 % of the leak
being measured, in the **negative** direction. It removes mass, so it biases
results towards *passing* a leaking valve. That is a fail-to-danger mode on an
acceptance test, not an accuracy inconvenience. See
[`measurement-budget.md`](measurement-budget.md) §2.1.

---

## Stage 2 — TwinCAT / CODESYS device configuration

| Step | Action | Pass criterion |
|---|---|---|
| 2.1 | Channel signal type = 4–20 mA, **Extended Range** (not Legacy — Legacy clips at nominal and suppresses the over/under-range diagnostics needed during calibration). | CoE object confirms Extended Range |
| 2.2 | Enable the **50 Hz FIR filter** on both channels. This is the difference between a usable noise floor and not. | Filter bit set in CoE |
| 2.3 | Confirm the process image maps each channel as **DINT (32-bit)**, not the legacy 16-bit image. *This is the actual fix for the PR2 defect — a change of the input's declared width, not of the scaling formula.* | Watch window shows DINT; values move in low double digits at zero load with the loop live |
| 2.4 | Apply a static 4 mA and 20 mA (bench current calibrator, or the conditioner's own zero/span) and **record raw counts at both ends, both channels**. | Two-point table logged |
| 2.5 | Transcribe the Stage 2.4 counts into `GVL_HydroLeak` (`c_diChA_Raw_4mA` / `_20mA`, ditto Ch B). | Constants match the logged table |
| 2.6 | Map `GVL_IO` diagnostic bits (under-range, over-range, error) for both channels. | Pulling the loop sets under-range within one cycle |

The Stage 2.4 numbers — not the datasheet LSB — are what the scaling constants
come from. Datasheet arithmetic and the real chain disagree, and the real chain
wins.

---

## Stage 3 — CODESYS ST build

Implemented. See `src/`:

```
src/
  GVLs/  GVL_IO.gvl                 raw process image, AT %I* DINT, both loops
         GVL_HydroLeak.gvl          calibration constants, ISO 5208 coefficients
  DUTs/  E_LeakState.dut            IDLE SETTLING TARED TESTING ALARM ABORTED
         E_ISO5208Class.dut         RATE_A .. RATE_D
  POUs/  PRG_HydroLeakDetection.st  sequence, scaling, verdict
         FB_LeastSquaresSlope.st    rolling-window regression, reusable
         F_ISO5208LimitMlMin.st     bore-scaled acceptance limit
         F_MinHoldMinutes.st        hold duration required for that threshold
```

Build order and rationale are in the file headers. The four decisions that
matter:

- **Rate is a fitted slope**, not a difference of consecutive samples.
  Differencing amplifies noise and carries no averaging; a regression over N
  samples suppresses zero-mean noise by ≈√N and cancels every constant offset
  in the chain.
- **Threshold is computed per test** from DN and rate class.
- **No negative clamp.** Clamping at zero rectifies noise into an apparent leak
  and conceals the net mass loss that reveals an unsealed vessel.
- **Fit quality gates the verdict.** Poor R² means the rig was disturbed —
  a retest, not a pass.
- **Hold adequacy is enforced.** Thermal drift is a fixed mass error over the
  hold, so as a rate error it scales as drift ÷ T. `F_MinHoldMinutes` derives
  the hold each valve needs, and a hold too short to resolve its own threshold
  cannot return a pass. Because the ISO 5208 limit scales with bore, small-bore
  valves need *longer* holds than large ones.
- **The slope window is derived from the hold**, not fixed. A fixed 10-minute
  window never fills on a 10-minute hold, so no verdict would ever be issued.

> **Before this system passes or fails anything:** the ISO 5208 coefficients in
> `GVL_HydroLeak` are placeholders and `F_ISO5208LimitMlMin` returns 0.0 for
> every class until they are populated from the controlled copy of the
> standard. This fails every valve rather than passing one against an invented
> limit. Populating them is a Stage 7 sign-off item.

---

## Stage 4 — Bench test (off-rig)

This is where the first real test log is generated.

| Test | Method | Target |
|---|---|---|
| 4.1 **Zero stability / blank** | Tared, unloaded, sealed, 60 min log, no vibration. | Slope ≈ 0. **Record the achieved mg/min — this is the working noise floor and it becomes the Rate A limit** (`c_rRateA_NoiseFloorMlMin`). It will be worse than the ELM3148 spec because it now includes cell, conditioner and cable. |
| 4.2 **Known-mass linearity** | Certified masses across range (10 g, 50 g, 200 g, 500 g). | Within the cell's stated non-linearity |
| 4.3 **Single-drip resolution** | Pipette ≈0.05 mL drops at measured intervals. | Each drop resolvable as a step in the DINT trace and in the CSV |
| 4.4 **Simulated micro-leak** | Syringe pump at 0.01, 0.02, 0.05 mL/min, 30 min each. | `rLeakRateMlMin` tracks set rate within ±20 % at 0.01 mL/min, tightening at higher rates |
| 4.5 **Thermal sensitivity** — *the pivotal test* | Repeat 4.1 while logging vessel temperature over a ≥2 °C swing. | Measure mg/°C of the **assembled chain** and **confirm the sign**. Populate `c_rDriftMgPerDegC`. Then re-run with correction enabled and record the residual — that residual sets the required hold for every valve. Getting the sign backwards doubles the error and still looks plausible |
| 4.6 **Vibration rejection** | Repeat 4.4 with the hydro pump running off-rig. | Slope stays within 4.4 tolerance. If not, revisit the FIR setting (2.2) or the mechanical isolation (1.3) **before rig install** |
| 4.7 **Creep characterisation** | Load the vessel, log 60 min unpressurised without taring. | Establishes how long settling must actually be. Adjust `c_tSettleTime` from the measured decay, don't assume 5 min |

Tests 4.1, 4.4 and 4.6 are the ones that decide whether the system works.

---

## Stage 5 — Rig integration (non-pressurised)

| Test | Method | Target |
|---|---|---|
| 5.1 | Mount on rig, dry-fit. Cycle `bStartTestCycle` 5×. | SETTLING → TARED → TESTING each time, no manual PLC intervention |
| 5.2 | Controlled drip at the valve stem/seat (syringe, not a real leak) mid-cycle. | ALARM latches; CSV captures the transition |
| 5.3 | Energise adjacent channels (upstream/downstream PT, thermocouples), re-run 5.1's zero-stability check. | Reading must not move — cross-talk check |
| 5.4 | Pull the XLR mid-test. | Under-range detected, state → ABORTED. **A broken loop reading 0 mA scales to a large negative mass; it must never read as a very tight valve** |
| 5.5 | Log the flowmeter (ch. B) alongside ch. A through a full cycle at 0.01–0.05 mL/min. | **Establish where the flowmeter stops reading.** At 0.01 mL/min most meters are at or below minimum flow, where they read low or stall. A flowmeter agreeing with "no leak" may simply be below its threshold — that is not corroboration. Do not arm the cross-check until this is characterised |

---

## Stage 6 — Pressurised validation

1. Known-good valve (zero expected leak), full hydrostatic hold per API 6A/6D
   duty. Both shell and seat phases logged.
2. Valve with an intentionally introduced micro-leak at a known rate
   (loosened gland or shim gap).
3. Compare `rLeakRateMlMin` against the ISO 5208 limit for that valve's DN and
   class. Confirm the alarm trips at the correct point — **not early (false
   reject) and not late (missed detection)**.
4. Repeat 5×; document the repeatability spread.
5. Run one test with the vessel lid **removed** as a negative control. The
   measured rate should drop by the evaporation figure from Stage 4.1. This
   demonstrates the sealing requirement to whoever signs the handover.

---

## Stage 7 — Sign-off and handover

- Populate ISO 5208 coefficients in `GVL_HydroLeak` from the controlled copy;
  have the values witnessed and recorded.
- Populate `c_rDriftMgPerDegC` and `c_rExpectedExcursionC` from Stage 4.5, and
  publish the resulting required-hold table per DN and rate class. Operators
  need to know before scheduling that a small-bore valve on a tight class needs
  a longer hold, not a shorter one.
- Archive Stage 4–6 datasets as the baseline.
- Write the per-unit commissioning checklist (Temp Cab §8.3 format:
  prototyping sign-off → rollout order → per-unit checklist).
- Record in the handover pack: the achieved noise floor, the mg/°C sensitivity,
  the settle time actually required, and the XLR pinout.

---

## Data logging

One CSV line per sample via `SysFile` (`AM_APPEND`). **Wait for write
completion before any `SysFileClose`.** One `.md` session log per test in
`docs/test-logs/`, dated, pass/fail per row, raw CSV attached.

Schema — see [`log-schema.md`](log-schema.md):

```
timestamp_iso8601, valve_id, dn_mm, rate_class, state,
raw_dint_cha, mass_g, captured_g,
raw_dint_chb, corroboration_eng,
vessel_temp_c, leak_rate_ml_min, threshold_ml_min, fit_r2, window_full
```

Raw counts are logged alongside engineering units deliberately: if a
calibration constant is later found to be wrong, every historical test can be
rescaled from the raw column instead of being discarded.

---

## Open items

| # | Item | Blocks |
|---|---|---|
| 1 | XLR pin numbers and pair isolation — bench continuity check | Stage 1.6 |
| 2 | ISO 5208 coefficients from the controlled copy | Any pass/fail verdict |
| 3 | Maximum captured mass per test → cell capacity | Purchase order |
| 4 | Hold duration in the governing procedure | Signal budget |
| 5 | Flowmeter minimum measurable flow — specify when purchasing | Stage 5.5 cross-check |
| 6 | Achieved mg/°C and its **sign** from Stage 4.5 | Every hold duration on the rig |
