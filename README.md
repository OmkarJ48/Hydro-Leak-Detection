# Hydro Leak Detection

Automated capture and quantification of micro-leaks during hydrostatic (shell
and seat) testing of valves, replacing the manual "count the drops" method with
a continuous gravimetric measurement that can be logged, trended and audited.

**Target sensitivity: 0.01 mL/min — 10 mg/min of captured water.**

Built to the Rebuild → Requalify → Repeat methodology used on Temperature
Cabinet Setpoint Control.

---

## Status

Design and pre-commissioning. Hardware not yet selected; see
[open items](docs/commissioning.md#open-items). The control logic is written
and the commissioning sequence is defined, but **the system cannot pass or fail
a valve yet** — the ISO 5208 coefficients are placeholders and
`F_ISO5208LimitMlMin` deliberately returns 0.0 until they are populated from
the controlled copy of the standard.

## Repository layout

```
src/
  GVLs/  GVL_IO.gvl                 raw process image, AT %I* DINT, both loops
         GVL_HydroLeak.gvl          calibration constants, ISO 5208 coefficients
  DUTs/  E_LeakState.dut            IDLE SETTLING TARED TESTING ALARM ABORTED
         E_ISO5208Class.dut         RATE_A .. RATE_D
  POUs/  PRG_HydroLeakDetection.st  sequence, scaling, verdict
         FB_LeastSquaresSlope.st    rolling-window regression, reusable
         F_ISO5208LimitMlMin.st     bore-scaled acceptance limit
         F_MinHoldMinutes.st        hold required to resolve that threshold
docs/
  commissioning.md                  Stages 1-7, every step with a pass criterion
  measurement-budget.md             what actually limits sensitivity, with numbers
  hardware-options.md               load cell vs LVDT vs ultrasonic, from the quotes
  log-schema.md                     CSV columns and why each exists
  test-logs/                        one dated .md per test session
  reference/                        superseded drafts, kept for provenance
tools/
  leak_budget.py                    re-runs the error budget under any assumptions
datasheets/  quotations/  drawings/ vendor source documents
```

## Measurement principle

Fluid escaping past the seat is collected in a **sealed** catch vessel resting
on a compression load cell. Leak rate is the **slope of captured mass against
time** over the pressurised hold — not the difference between two instantaneous
readings.

That choice does the heavy lifting. A slope fit is blind to every constant
offset in the chain — cell zero balance, tare error, vessel mass, absolute
calibration error — leaving only drift *within* the hold as error. It also
produces a rate, which is the unit the acceptance criteria are written in.

For water, 1 g ≈ 1 mL (0.998 g/mL at 20 °C). Other fluids: density is a
per-test input.

## What actually limits sensitivity

Not resolution. The ELM3148 is a 24-bit converter; mapping 4–20 mA onto
0–1000 g gives ~0.15 mg/count, so a 10 mg/min leak advances ~67 counts/min.

For a 20-minute hold carrying 200 mg of signal:

| Source | Error | % of signal |
|---|---|---|
| **Evaporation, open Ø80 mm vessel** | **84–168 mg** | **42–84 %** |
| Zero drift, 1 kg cell, 1 °C | 50 mg | 25 % |
| Creep, load not pre-settled | 50 mg | 25 % |
| Quantisation, raw value read as `INT` | 30 mg | 15 % |

Evaporation is the one that matters most, and not because it is largest: it
*removes* mass, so it biases towards **passing a leaking valve**. Five fixes
cost nothing — seal the vessel, extend the hold, pre-settle before taring,
declare the input `DINT`, fit a slope instead of differencing. Together they
take the budget from 107–149 % of signal to about 3 %.

Full derivation: [`docs/measurement-budget.md`](docs/measurement-budget.md).
Re-run it under your own assumptions:

```bash
python tools/leak_budget.py --capacity 250 --hold 60 --sealed --settled
```

## Field wiring

The 4-pin XLR carries **two independent 4–20 mA loops** (two positives, two
negatives), not one redundant loop:

| Loop | Channel | Purpose |
|---|---|---|
| 1 | ELM3148 A | Primary load cell — leak mass |
| 2 | ELM3148 B | Flowmeter — independent physics, corroboration only |

Pin numbers are **not documented anywhere** and must be established by
continuity check before wiring goes live —
[Stage 1.2](docs/commissioning.md#12--the-4-pin-xlr).

## Acceptance thresholds

ISO 5208 liquid rates scale with nominal bore, so the limit is computed per test
from the valve's DN and rate class and arrives with the valve ID. A compiled-in
limit would force a rebuild for every valve size.

## Applicable standards

API 6A, API 6D and API 17D govern the test procedure; ISO 5208 defines the
leakage rate classes. These are licensed documents and are **not** redistributed
here — obtain them through the organisation's subscription.

## Development

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

`Sub-main` is the integration branch. Work happens on feature branches and
merges via pull request.
