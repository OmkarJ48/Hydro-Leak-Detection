# Test log schema

One CSV per test cycle, written by `PRG_HydroLeakDetection` via `SysFile`
(`AM_APPEND`). Filename: `<valve_id>_<yyyymmdd-hhmmss>.csv`.

| Column | Type | Units | Notes |
|---|---|---|---|
| `timestamp_iso8601` | string | — | PLC clock, UTC |
| `valve_id` | string | — | As entered at the HMI |
| `dn_mm` | real | mm | Nominal bore, per test |
| `rate_class` | string | — | `A`–`D`, ISO 5208 |
| `state` | string | — | `E_LeakState` name |
| `raw_dint_cha` | dint | counts | **Raw, unscaled** |
| `mass_g` | real | g | Absolute mass on the cell |
| `captured_g` | real | g | Tared. **May be negative — do not clamp** |
| `raw_dint_chb` | dint | counts | Corroborating loop, raw |
| `corroboration_eng` | real | — | Scaled ch. B |
| `vessel_temp_c` | real | °C | Blank if no temp channel |
| `leak_rate_ml_min` | real | mL/min | Fitted slope ÷ density |
| `threshold_ml_min` | real | mL/min | Active limit for this valve |
| `fit_r2` | real | — | 0.0–1.0 |
| `window_full` | bool | — | Rate is meaningless while false |

## Why raw counts are logged alongside engineering units

If a calibration constant is later found wrong — and Stage 2.4 is done once, by
hand, early — every historical test can be rescaled from the raw column. Log
only engineering units and the whole archive is discarded instead.

## Why `captured_g` is never clamped

Negative captured mass is a measurement, not an error. It means the vessel is
losing water faster than the valve leaks into it: an unsealed lid, a thermal
excursion, or a drift problem. Clamping at zero hides exactly the symptom that
would have caught an evaporation fault, and rectifies noise into an apparent
leak on a tight valve.

## Session log

One `docs/test-logs/YYYY-MM-DD-<stage>-<description>.md` per session, with the
pass/fail row from the relevant `commissioning.md` table, the observed value,
and the CSV attached. Template: `docs/test-logs/_TEMPLATE.md`.
