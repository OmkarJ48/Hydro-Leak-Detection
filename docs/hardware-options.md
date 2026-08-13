# Sensing options — comparison of quoted hardware

Derived from the quotations held in this repository. Prices are **net of VAT**
unless stated. All quotations are dated June 2026 and carry 30-day validity, so
they will need refreshing before any order.

---

## 1. Gravimetric (load cell) — the primary candidate

| Ref | Cell | Capacity | Amplifier | Set total (net) | Delivery |
|---|---|---|---|---|---|
| Novatech QU-24976 | F238-Z | 1 kg | SGA/D | **£1,420** | 3 weeks |
| AppMeas 0000917793 | Weighing platform 100×100 | 1 kg | TX20-AN | **£1,553** | 4 weeks |
| RDP SC26-00387 | Model 13 | 1 kg (comp. only) | DR7DC | **£1,712** | 7–10 days |
| RDP SC26-00399 | Model 31 | 1 kg | DR7DC | **£2,261** | 2 weeks |
| RDP SC26-00399 | Model 31 | 500 g | DR7DC | **£2,449** | **12 weeks** |
| RDP SC26-00399 | Model 31 | 250 g | DR7DC | **£2,788** | 2 weeks |

Relevant specifications for the two best-documented options:

| | Novatech F238 | AppMeas OBUG |
|---|---|---|
| Zero drift / °C | ±0.005 %RL | <0.005 %RC |
| Creep | ±0.05 % of **applied load** / 20 min | <0.08 % of **rated capacity** / 30 min *(confirm)* |
| Non-linearity | ±0.05 %RL | <0.03 %RC |
| Rated output | 2.0–2.2 mV/V | 1.5 mV/V (≤2 kg) |
| Compensated range | −10 to +50 °C | −10 to +40 °C |
| Sealing | Unsealed *(quote adds anti-vibration / condensate coating)* | IP65 (≤2 kg) |

### Observations

**Reducing capacity does not save money here.** The 250 g Model 31 set is
£1,368 *more* than the 1 kg Model 13 set. The case for lower capacity rests
entirely on thermal drift (see `measurement-budget.md` §2.2), not cost.

**There is no quotation for a 250 g platform from Applied Measurements.** Their
OBUG catalogue part covers 0–250 g and the quoted assembly is 0–1 kg. Given the
OBUG's drift specification and the far lower price point, **a quotation for the
0–250 g platform with the TX20-AN should be requested** before deciding. It is
plausibly the best value option in the list and is currently unrepresented.

**The OBUG creep specification needs clarifying with the vendor.** If creep is
genuinely referenced to rated capacity rather than applied load, the OBUG is
materially worse than the F238 for this application despite the better headline
drift figure. This single question could invert the recommendation.

**Fluid exposure.** The F238 is quoted unsealed with protective coating; RDP
state explicitly that their cell, cable and amplifier must be kept clear of
fluid. The AppMeas OBUG is IP65. Given a catch vessel of water sitting directly
on the cell, sealing is not a detail — a splash or a condensation path to the
bridge circuitry is a calibration shift, not an obvious failure.

**Amplifier filtering.** Only the Novatech SGA/D documents switch-selectable
low-pass filtering (1 Hz–5 kHz). Set to 1 Hz. Confirm equivalent filtering is
available on the DR7DC and TX20-AN before selecting either.

---

## 2. Level sensing (LVDT) — viable only for very small capture volumes

| Ref | Part | Range | Set total (net) | Delivery |
|---|---|---|---|---|
| RDP SC26-00427 | MD5/500HK-L25, non-submersible | ±12.5 mm | **£594** | 7–10 days |
| RDP SC26-00428 | MD5/500W-L25, submersible | ±12.5 mm | **£813** | 6–8 weeks |

Level sensing trades mass resolution for **geometry**: the narrower the vessel,
the larger the level change per unit volume.

Level rise produced by a 0.01 mL/min leak:

| Vessel bore | Area | Level rise | Volume within ±12.5 mm stroke |
|---|---|---|---|
| Ø80 mm beaker | 50.3 cm² | 2 µm/min | 126 mL |
| Ø25 mm | 4.9 cm² | 20 µm/min | 12.3 mL |
| Ø10 mm standpipe | 0.79 cm² | **127 µm/min** | **2.0 mL** |
| Ø6 mm standpipe | 0.28 cm² | 354 µm/min | 0.7 mL |

In a 10 mm standpipe the signal is 127 µm/min against an LVDT with effectively
infinite resolution and 0.25 % linearity (±62 µm over the full 25 mm stroke,
and largely cancelled by a slope fit over a small sub-range). At £594 this is
the cheapest option by a wide margin, and it is immune to the thermal drift
problem that dominates the gravimetric budget.

**Its limits are what decide it:**

- **Total capture is ~2 mL** in a 10 mm bore. Beyond that the LVDT saturates.
  Acceptable if a gross leak simply needs to register as *out of range* — a
  valve leaking a hundred times the threshold does not need precise
  quantification. Unacceptable if the same rig must quantify large leaks.
- **A float is required**, and floats suffer stiction and surface-tension
  pinning against the standpipe wall. The failure mode is a stick-slip
  staircase rather than a smooth ramp — which a slope fit will happily average
  into a plausible-looking but wrong answer. This is the main technical risk
  and would need proving on a bench rig before commitment.
- **Evaporation still applies**, and in a narrow bore it is much smaller in
  absolute terms (0.79 cm² instead of 50 cm²) — around 0.1 mg/min, i.e. ~1 % of
  the signal. Sealing remains sensible but is no longer critical.

The narrow standpipe is worth bench-testing precisely because it attacks the
two dominant error terms — thermal drift and evaporation — by geometry rather
than by money.

---

## 3. Ultrasonic level — not suitable as the primary measurement

| Ref | Part | Range | Unit price |
|---|---|---|---|
| ifm 203418872 | UGT524 (M18) | 40–300 mm | £188.40 |
| ifm 203418872 | UGT525 (M18) | 60–800 mm | £188.40 |
| ifm 203418872 | UGT526 (M18) | 80–1200 mm | £188.40 |
| Pepperl+Fuchs | UB120 / 14 mm series | *(datasheet only)* | — |

Ultrasonic sensing fails this application on two independent grounds:

1. **Resolution.** Sub-millimetre resolution against a 0.01 mL/min leak requires
   a narrow bore to be useful — but in a Ø80 mm vessel, 0.5 mm of resolution is
   25 mL, which is over 40 hours of signal.
2. **Geometry.** An M18 sensor with a 40 mm minimum dead band cannot be aimed
   down a 10 mm standpipe. Beam divergence and the sensor face diameter both
   exceed the bore.

**Recommended role:** vessel-full / overflow detection and gross-leak
annunciation, mounted over a wide-mouth secondary containment. That is a real
and useful function — it protects the load cell from overload and gives the
operator an unambiguous gross-leak trip — but it is not the micro-leak
measurement.

---

## 4. Suggested next actions

1. Request an Applied Measurements quotation for the **0–250 g OBUG platform**
   with TX20-AN and UKAS calibration. Currently the cheapest credible route to
   the low-drift configuration, and it is missing from the set.
2. Ask Applied Measurements to **confirm the creep reference basis** (rated
   capacity or applied load). This determines whether the OBUG or the F238 is
   the better cell.
3. Ask RDP and Applied Measurements what **low-pass filtering** the DR7DC and
   TX20-AN provide.
4. Bench-test the **Ø10 mm standpipe + float + LVDT** arrangement for float
   stiction before ruling it in or out. At £594 with 7–10 day delivery it is
   cheap to disprove, and if it works it is both cheaper and fundamentally more
   robust than the gravimetric route.
5. Refresh all quotations — every one has expired.
