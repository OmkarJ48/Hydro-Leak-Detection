(*
    F_MinHoldMinutes

    Minimum pressurised hold duration for the measurement to be trustworthy
    against a given acceptance threshold.

    Thermal zero drift is a fixed MASS error accumulated over the hold, not a
    rate error. Expressed as a rate it therefore divides by the hold duration:

        rate error (mg/min) = total drift (mg) / hold (min)

    So the hold needed to keep drift below an acceptable fraction of the
    threshold is:

        T_min = k * TotalDrift_mg / (Threshold_mL_min * density_g_mL)

    where k = 1 / acceptable_fraction  (k = 5 for a 20 % error allowance).

    This is why "hold duration varies by valve size and spec" cannot simply be
    accepted as an input. The acceptance threshold scales with nominal bore, so
    a small-bore valve on a tight rate class needs a LONGER hold than a large
    one -- the opposite of what test schedules usually assume. Rather than
    trusting the schedule, the program computes what this rig actually needs
    and refuses to issue a verdict on a hold that was too short.

    TotalDrift_mg comes from the Stage 4.5 thermal characterisation, not from
    the datasheet: it is the measured mg/degC of the assembled chain multiplied
    by the temperature excursion the vessel actually sees during a hold.

    Worked example -- 1 kg cell, open workshop:
        50 mg/degC * 2 degC = 100 mg total drift
        threshold 0.01 mL/min, k = 5
        T_min = 5 * 100 / (0.01 * 1000 * 0.998) = 50 minutes
*)
FUNCTION F_MinHoldMinutes : REAL
VAR_INPUT
    rThresholdMlMin  : REAL;   (* active ISO 5208 limit for this valve *)
    rTotalDriftMg    : REAL;   (* from Stage 4.5, for the expected excursion *)
    rDensityGPerMl   : REAL;
    rErrorAllowance  : REAL;   (* e.g. 0.20 for 20 % *)
END_VAR
VAR
    rK : REAL;
END_VAR

(* A zero or negative threshold means Rate A bounded by the noise floor, or an
   unpopulated ISO 5208 coefficient. Neither can produce a meaningful hold
   requirement, so demand the configured maximum rather than returning zero --
   returning zero would silently declare any hold long enough. *)
IF rThresholdMlMin <= 0.0 OR rDensityGPerMl <= 0.0 OR rErrorAllowance <= 0.0 THEN
    F_MinHoldMinutes := GVL_HydroLeak.c_rMaxPracticalHoldMin;
    RETURN;
END_IF

rK := 1.0 / rErrorAllowance;

F_MinHoldMinutes := (rK * rTotalDriftMg)
                    / (rThresholdMlMin * rDensityGPerMl * 1000.0);
