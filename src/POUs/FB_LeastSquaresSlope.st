(*
    FB_LeastSquaresSlope

    Rolling-window least-squares fit of mass against time. Reusable -- nothing
    in here is leak-specific.

    Why a slope and not a difference of consecutive samples:
    differencing amplifies noise (the difference of two noisy samples has ~1.4x
    the noise of one) and carries no averaging. A regression over N samples
    suppresses zero-mean noise by ~sqrt(N) and, more importantly, is blind to
    every CONSTANT offset in the chain -- cell zero balance, tare error, vessel
    mass, absolute calibration error. Only drift occurring inside the window
    survives into the result.

    Accumulators are LREAL. Sum-of-squares terms grow as n*t^2; over a
    60-minute window at 1 Hz that exceeds the ~7 significant digits a 32-bit
    REAL carries, and the fit silently degrades rather than failing.

    The window is maintained incrementally (add new, subtract outgoing) for
    O(1) cost per cycle. Repeated subtraction accumulates rounding error over
    long runs, so the sums are fully recomputed from the buffer every
    c_udiRebaseInterval updates.

    rR2 is reported so the caller can reject a window that is not usefully
    linear. Unsettled creep, a knocked rig, and float stick-slip all show up as
    a poor fit rather than as an obviously wrong number.
*)
FUNCTION_BLOCK FB_LeastSquaresSlope
VAR_INPUT
    bEnable      : BOOL;
    bReset       : BOOL;
    rTimeSec     : REAL;
    rValue       : REAL;
    uiWindowSize : UINT := 600;
END_VAR
VAR_OUTPUT
    rSlopePerSec : REAL;
    rSlopePerMin : REAL;
    rR2          : REAL;
    rIntercept   : REAL;
    uiCount      : UINT;    (* samples currently in the window *)
    bWindowFull  : BOOL;
    bValid       : BOOL;
END_VAR
VAR CONSTANT
    c_uiMaxWindow        : UINT  := 3600;   (* 1 hour at 1 Hz *)
    c_udiRebaseInterval  : UDINT := 10000;
END_VAR
VAR
    arT      : ARRAY[0..3599] OF LREAL;
    arV      : ARRAY[0..3599] OF LREAL;
    uiHead   : UINT;
    uiN      : UINT;
    uiWin    : UINT;
    udiSince : UDINT;

    lrN, lrSt, lrSv, lrStt, lrSvv, lrStv : LREAL;
    lrSxx, lrSyy, lrSxy, lrSlope : LREAL;
    lrOutT, lrOutV : LREAL;
    i : UINT;
END_VAR

IF bReset THEN
    uiHead := 0;  uiN := 0;  udiSince := 0;
    lrN := 0.0; lrSt := 0.0; lrSv := 0.0;
    lrStt := 0.0; lrSvv := 0.0; lrStv := 0.0;
    rSlopePerSec := 0.0;  rSlopePerMin := 0.0;
    rR2 := 0.0;  rIntercept := 0.0;
    uiCount := 0;  bWindowFull := FALSE;  bValid := FALSE;
    RETURN;
END_IF

(* Clamp the requested window to the allocated buffer. *)
uiWin := uiWindowSize;
IF uiWin > c_uiMaxWindow THEN
    uiWin := c_uiMaxWindow;
END_IF
IF uiWin < 2 THEN
    uiWin := 2;
END_IF

IF bEnable THEN
    (* Evict the oldest sample once the window is full. *)
    IF uiN >= uiWin THEN
        lrOutT := arT[uiHead];
        lrOutV := arV[uiHead];
        lrN    := lrN   - 1.0;
        lrSt   := lrSt  - lrOutT;
        lrSv   := lrSv  - lrOutV;
        lrStt  := lrStt - lrOutT * lrOutT;
        lrSvv  := lrSvv - lrOutV * lrOutV;
        lrStv  := lrStv - lrOutT * lrOutV;
        uiN    := uiN - 1;
    END_IF

    arT[uiHead] := TO_LREAL(rTimeSec);
    arV[uiHead] := TO_LREAL(rValue);
    lrN   := lrN   + 1.0;
    lrSt  := lrSt  + arT[uiHead];
    lrSv  := lrSv  + arV[uiHead];
    lrStt := lrStt + arT[uiHead] * arT[uiHead];
    lrSvv := lrSvv + arV[uiHead] * arV[uiHead];
    lrStv := lrStv + arT[uiHead] * arV[uiHead];

    uiHead := (uiHead + 1) MOD uiWin;
    uiN    := uiN + 1;

    (* Periodic exact rebase against accumulated subtraction error. *)
    udiSince := udiSince + 1;
    IF udiSince >= c_udiRebaseInterval THEN
        udiSince := 0;
        lrN := 0.0; lrSt := 0.0; lrSv := 0.0;
        lrStt := 0.0; lrSvv := 0.0; lrStv := 0.0;
        FOR i := 0 TO uiN - 1 DO
            lrN   := lrN   + 1.0;
            lrSt  := lrSt  + arT[i];
            lrSv  := lrSv  + arV[i];
            lrStt := lrStt + arT[i] * arT[i];
            lrSvv := lrSvv + arV[i] * arV[i];
            lrStv := lrStv + arT[i] * arV[i];
        END_FOR
    END_IF
END_IF

uiCount     := uiN;
bWindowFull := (uiN >= uiWin);

IF lrN < 2.0 THEN
    bValid := FALSE;
    RETURN;
END_IF

lrSxx := lrStt - (lrSt * lrSt) / lrN;
lrSyy := lrSvv - (lrSv * lrSv) / lrN;
lrSxy := lrStv - (lrSt * lrSv) / lrN;

(* Sxx is zero only if every sample in the window shares one timestamp. *)
IF lrSxx <= 0.0 THEN
    bValid := FALSE;
    RETURN;
END_IF

lrSlope      := lrSxy / lrSxx;
rSlopePerSec := LREAL_TO_REAL(lrSlope);
rSlopePerMin := LREAL_TO_REAL(lrSlope * 60.0);
rIntercept   := LREAL_TO_REAL((lrSv - lrSlope * lrSt) / lrN);

(* Syy = 0 is a perfectly flat trace -- a tight valve, not an error. *)
IF lrSyy > 0.0 THEN
    rR2 := LREAL_TO_REAL((lrSxy * lrSxy) / (lrSxx * lrSyy));
ELSE
    rR2 := 1.0;
END_IF

bValid := TRUE;
