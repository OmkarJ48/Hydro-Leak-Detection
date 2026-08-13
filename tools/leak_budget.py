#!/usr/bin/env python3
"""Error budget calculator for the gravimetric leak detection method.

Reproduces the numbers in docs/measurement-budget.md so they can be re-checked
against different assumptions -- in particular the three unknowns that currently
gate the hardware decision: load cell capacity, hold duration, and whether the
catch vessel is temperature controlled.

    python tools/leak_budget.py --capacity 250 --hold 60 --vessel-dia 80

Everything is computed in milligrams of water.
"""

import argparse
import math

# Still-air evaporation from a free water surface at ~20 C, ~50 % RH.
# Wide band because the rate depends strongly on air movement over the surface.
EVAP_LOW_KG_M2_H = 0.05
EVAP_HIGH_KG_M2_H = 0.10

# Zero drift per degree, as a fraction of rated capacity. Novatech F238 and
# Applied Measurements OBUG both specify 0.005 %/C.
ZERO_DRIFT_FRAC_PER_C = 0.005 / 100.0

# ELM3148: 24-bit converter over a +/-20 mA range; 4-20 mA uses 16 mA of it.
ADC_BITS = 24
ADC_SPAN_MA = 40.0
SIGNAL_SPAN_MA = 16.0


def evaporation_mg_per_min(vessel_dia_mm: float) -> tuple[float, float]:
    area_m2 = math.pi * (vessel_dia_mm / 2000.0) ** 2
    low = EVAP_LOW_KG_M2_H * area_m2 * 1e6 / 60.0
    high = EVAP_HIGH_KG_M2_H * area_m2 * 1e6 / 60.0
    return low, high


def zero_drift_mg(capacity_g: float, delta_c: float) -> float:
    return capacity_g * 1000.0 * ZERO_DRIFT_FRAC_PER_C * delta_c


def quantisation_mg(capacity_g: float, as_int16: bool) -> float:
    if as_int16:
        return capacity_g * 1000.0 / 32767.0
    counts = (SIGNAL_SPAN_MA / ADC_SPAN_MA) * (2 ** ADC_BITS)
    return capacity_g * 1000.0 / counts


def creep_mg(applied_load_g: float, settled: bool) -> float:
    """Novatech F238: +/-0.05 % of applied load over 20 minutes.

    If the vessel is pre-settled before the hold, the only load creeping during
    measurement is the accumulated leak itself, which is negligible.
    """
    if settled:
        return 0.0005 * 0.2  # 0.05 % of ~200 mg of accumulated leak
    return 0.0005 * applied_load_g * 1000.0


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--target", type=float, default=0.01,
                   help="leak rate to resolve, mL/min (default 0.01)")
    p.add_argument("--capacity", type=float, default=1000.0,
                   help="load cell rated capacity, grams (default 1000)")
    p.add_argument("--hold", type=float, default=20.0,
                   help="pressurised hold duration, minutes (default 20)")
    p.add_argument("--vessel-dia", type=float, default=80.0,
                   help="catch vessel opening diameter, mm (default 80)")
    p.add_argument("--delta-c", type=float, default=1.0,
                   help="temperature swing across the hold, degrees C (default 1)")
    p.add_argument("--applied-load", type=float, default=100.0,
                   help="static load on the cell, grams (default 100)")
    p.add_argument("--sealed", action="store_true",
                   help="catch vessel is sealed (removes evaporation)")
    p.add_argument("--settled", action="store_true",
                   help="load pre-settled before the hold (removes creep)")
    p.add_argument("--int16", action="store_true",
                   help="raw value truncated to 16-bit INT rather than DINT")
    a = p.parse_args()

    signal_mg = a.target * 1000.0 * a.hold  # 1 mL water ~ 1 g

    rows = []

    if a.sealed:
        rows.append(("Evaporation (vessel sealed)", 0.0, 0.0))
    else:
        lo, hi = evaporation_mg_per_min(a.vessel_dia)
        rows.append((f"Evaporation, open Ø{a.vessel_dia:g} mm",
                     lo * a.hold, hi * a.hold))

    d = zero_drift_mg(a.capacity, a.delta_c)
    rows.append((f"Zero drift, {a.capacity:g} g cell, {a.delta_c:g} °C", d, d))

    c = creep_mg(a.applied_load, a.settled)
    rows.append(("Creep" + (" (pre-settled)" if a.settled else " (not settled)"), c, c))

    q = quantisation_mg(a.capacity, a.int16)
    rows.append(("Quantisation" + (" (INT16)" if a.int16 else " (24-bit DINT)"), q, q))

    print(f"\nTarget            {a.target:g} mL/min")
    print(f"Hold              {a.hold:g} min")
    print(f"Signal available  {signal_mg:.1f} mg\n")
    print(f"{'Error source':<42}{'mg':>16}{'% of signal':>16}")
    print("-" * 74)

    tot_lo = tot_hi = 0.0
    for name, lo, hi in rows:
        tot_lo += lo
        tot_hi += hi
        mag = f"{lo:.1f}" if lo == hi else f"{lo:.1f}–{hi:.1f}"
        pct = (f"{100 * lo / signal_mg:.1f}" if lo == hi
               else f"{100 * lo / signal_mg:.1f}–{100 * hi / signal_mg:.1f}")
        print(f"{name:<42}{mag:>16}{pct:>16}")

    print("-" * 74)
    mag = f"{tot_lo:.1f}" if tot_lo == tot_hi else f"{tot_lo:.1f}–{tot_hi:.1f}"
    pct = (f"{100 * tot_lo / signal_mg:.1f}" if tot_lo == tot_hi
           else f"{100 * tot_lo / signal_mg:.1f}–{100 * tot_hi / signal_mg:.1f}")
    print(f"{'Worst-case sum (all same sign)':<42}{mag:>16}{pct:>16}")

    verdict = "viable" if tot_hi < 0.25 * signal_mg else "NOT viable as configured"
    print(f"\nAgainst a 25 % error allowance: {verdict}\n")


if __name__ == "__main__":
    main()
