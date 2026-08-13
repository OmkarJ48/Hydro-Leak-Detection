(*
    FB_LeakRateEstimator

    Incremental least-squares fit of captured mass against time, giving leak
    rate as the slope of that line.

    Why a slope rather than a difference of two readings:
    fitting a slope is blind to any constant offset in the measurement chain --
    load cell zero balance, tare error, the mass of the catch vessel, absolute
    calibration error. Only drift occurring *within* the measurement window
    survives into the result. See docs/measurement-budget.md.

    Accumulators are LREAL, not REAL. Sum-of-squares terms grow as n * t^2; over
    a 60-minute window at 1 Hz that exceeds the ~7 significant digits a 32-bit
    REAL carries, and the fit silently degrades.

    The coefficient of determination (rR2) is reported so the caller can reject
    a window that is not usefully linear -- unsettled creep, a knocked rig, or
    float stick-slip all show up as a poor fit rather than as an obviously
    wrong number.
*)
FUNCTION_BLOCK FB_LeakRateEstimator
VAR_INPUT
    bEnable      : BOOL;   // TRUE while samples should be accumulated
    bReset       : BOOL;   // Clears all accumulators
    rTimeSec     : REAL;   // Time since window start, seconds
    rMassGrams   : REAL;   // Tared captured mass, grams
END_VAR
VAR_OUTPUT
    rRateGPerSec : REAL;   // Fitted slope, grams/second
    rRateGPerMin : REAL;   // Fitted slope, grams/minute
    rR2          : REAL;   // Coefficient of determination, 0.0 .. 1.0
    udiSamples   : UDINT;  // Samples in the current fit
    bValid       : BOOL;   // TRUE once the fit is numerically defined
END_VAR
VAR
    lrN   : LREAL;
    lrSt  : LREAL;         // sum t
    lrSm  : LREAL;         // sum m
    lrStt : LREAL;         // sum t*t
    lrSmm : LREAL;         // sum m*m
    lrStm : LREAL;         // sum t*m
    lrSxx : LREAL;
    lrSyy : LREAL;
    lrSxy : LREAL;
    lrSlope : LREAL;
END_VAR

IF bReset THEN
    lrN   := 0.0;
    lrSt  := 0.0;
    lrSm  := 0.0;
    lrStt := 0.0;
    lrSmm := 0.0;
    lrStm := 0.0;
    rRateGPerSec := 0.0;
    rRateGPerMin := 0.0;
    rR2          := 0.0;
    udiSamples   := 0;
    bValid       := FALSE;
    RETURN;
END_IF

IF bEnable THEN
    lrN   := lrN   + 1.0;
    lrSt  := lrSt  + TO_LREAL(rTimeSec);
    lrSm  := lrSm  + TO_LREAL(rMassGrams);
    lrStt := lrStt + TO_LREAL(rTimeSec)   * TO_LREAL(rTimeSec);
    lrSmm := lrSmm + TO_LREAL(rMassGrams) * TO_LREAL(rMassGrams);
    lrStm := lrStm + TO_LREAL(rTimeSec)   * TO_LREAL(rMassGrams);
    udiSamples := LREAL_TO_UDINT(lrN);
END_IF

(* At least two distinct samples are needed before a slope exists. *)
IF lrN < 2.0 THEN
    bValid := FALSE;
    RETURN;
END_IF

lrSxx := lrStt - (lrSt * lrSt) / lrN;
lrSyy := lrSmm - (lrSm * lrSm) / lrN;
lrSxy := lrStm - (lrSt * lrSm) / lrN;

(* Sxx is zero only if every sample carries the same timestamp. *)
IF lrSxx <= 0.0 THEN
    bValid := FALSE;
    RETURN;
END_IF

lrSlope      := lrSxy / lrSxx;
rRateGPerSec := LREAL_TO_REAL(lrSlope);
rRateGPerMin := LREAL_TO_REAL(lrSlope * 60.0);

(* Syy is zero for a perfectly flat mass trace, which is a legitimate result
   (a tight valve) rather than an error. Report a perfect fit. *)
IF lrSyy > 0.0 THEN
    rR2 := LREAL_TO_REAL((lrSxy * lrSxy) / (lrSxx * lrSyy));
ELSE
    rR2 := 1.0;
END_IF

bValid := TRUE;
