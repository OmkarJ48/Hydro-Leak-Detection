(*
    PRG_HydroLeakDetection

    Gravimetric micro-leak detection for hydrostatic valve testing.
    Target sensitivity 0.01 mL/min == 10 mg/min of captured water.

    Replaces PR2_Leak_Detection, which is retired rather than extended. Its
    tare and settle pattern carried over; its scaling and its output did not.

    Changes from PR2, and why each one matters:

    1. Raw input DINT via GVL_IO, not INT. Reading the 24-bit ELM3148 as 16
       bits gave 30.5 mg/count -- a full 20-minute signal spanning six counts.

    2. Scaling endpoints from the Stage 2.4 bench calibration, not 0/32767.
       32767 is a 16-bit convention, not a property of this converter.

    3. Output is a RATE, fitted by least squares over a rolling window. PR2
       reported an instantaneous mass difference and labelled it leak volume.
       Acceptance criteria are written as rates, and a slope cancels every
       constant offset in the chain.

    4. Threshold computed per test from valve DN and ISO 5208 rate class.

    5. Settle time minutes, not 3 s, with tare at the END of it. Three seconds
       damps suspension swing; creep decays over minutes and mimics a leak.

    6. No negative clamp. PR2 clamped at zero, which rectifies noise into a
       positive bias -- an apparent leak on a tight valve -- and conceals net
       mass LOSS, the signature of an unsealed catch vessel. Evaporation from
       an open vessel is 40-85 % of the signal and removes mass, so it biases
       towards PASSING a leaking valve. See docs/measurement-budget.md 2.1.

    7. Fit quality gates the verdict. A disturbed run is a retest, not a pass.

    Corroborating channel B is read and logged but does not yet gate the
    verdict -- that cross-check is defined in docs/commissioning.md Stage 5.3
    and should not be armed until the bench tests establish its noise floor.
*)
PROGRAM PRG_HydroLeakDetection
VAR
    (* --- Per-test inputs, supplied with the valve ID from the HMI --- *)
    bStartTestCycle        : BOOL;
    bOperatorAbort         : BOOL;
    sValveId               : STRING(32);
    rValveDN_mm            : REAL;                     (* nominal bore *)
    eRateClass             : E_ISO5208Class;           (* A / B / C / D *)
    rFluidDensityGPerMl    : REAL := 0.998;
    tHoldDuration          : TIME := T#20M;

    (* --- Scaled process values --- *)
    rAbsoluteMassG         : REAL;
    rTareMassG             : REAL;
    rCapturedMassG         : REAL;    (* may legitimately go negative *)
    rCorroborationEng      : REAL;
    rVesselTempC           : REAL;

    (* --- Result --- *)
    rLeakRateMlMin         : REAL;
    rActiveThresholdMlMin  : REAL;
    rFitR2                 : REAL;
    bResultTrustworthy     : BOOL;
    bLeakWithinLimit       : BOOL;
    bTestComplete          : BOOL;

    (* --- State --- *)
    eState                 : E_LeakState := E_LeakState.IDLE;
    rElapsedSec            : REAL;

    (* --- Instances --- *)
    fbSettleTimer          : TON;
    fbDiscardTimer         : TON;
    fbHoldTimer            : TON;
    fbAlarmDebounce        : TON;
    fbSlope                : FB_LeastSquaresSlope;

    (* --- Scratch --- *)
    rSpanCounts            : REAL;
    bLoopFault             : BOOL;
END_VAR

// =============================================================================
// 1. Loop health
// =============================================================================
(* Under-range means the 4-20 mA loop is open: a pulled cable, a dead
   conditioner, or an XLR backed out of its shell. This must abort the test.
   A broken loop reading 0 mA scales to a large NEGATIVE mass, which a naive
   implementation would report as a very tight valve. *)
bLoopFault := GVL_IO.bChAError OR GVL_IO.bChAUnderrange OR GVL_IO.bChAOverrange;

// =============================================================================
// 2. Scaling -- from the Stage 2.4 two-point calibration
// =============================================================================
rSpanCounts := DINT_TO_REAL(GVL_HydroLeak.c_diChA_Raw_20mA - GVL_HydroLeak.c_diChA_Raw_4mA);

IF rSpanCounts <> 0.0 THEN
    rAbsoluteMassG := (DINT_TO_REAL(GVL_IO.diRawMassChA - GVL_HydroLeak.c_diChA_Raw_4mA)
                       / rSpanCounts) * GVL_HydroLeak.c_rChA_SpanGrams;
ELSE
    rAbsoluteMassG := 0.0;
END_IF

rSpanCounts := DINT_TO_REAL(GVL_HydroLeak.c_diChB_Raw_20mA - GVL_HydroLeak.c_diChB_Raw_4mA);
IF rSpanCounts <> 0.0 THEN
    rCorroborationEng := (DINT_TO_REAL(GVL_IO.diRawCorrobChB - GVL_HydroLeak.c_diChB_Raw_4mA)
                          / rSpanCounts) * GVL_HydroLeak.c_rChB_SpanEng;
ELSE
    rCorroborationEng := 0.0;
END_IF

// =============================================================================
// 3. Acceptance threshold -- per test, from DN and rate class
// =============================================================================
(* ISO 5208 liquid rates are expressed per unit of nominal bore, so the limit
   is recomputed for every valve rather than compiled in. Coefficients live in
   GVL_HydroLeak and are PLACEHOLDERS until verified against the controlled
   copy of the standard -- see that file's header. *)
rActiveThresholdMlMin := F_ISO5208LimitMlMin(eClass := eRateClass, rDN_mm := rValveDN_mm);

// =============================================================================
// 4. Timers -- serviced before the state logic so .Q and .ET are current
// =============================================================================
fbSettleTimer( IN := (eState = E_LeakState.SETTLING), PT := GVL_HydroLeak.c_tSettleTime);
fbDiscardTimer(IN := (eState = E_LeakState.TARED),    PT := GVL_HydroLeak.c_tDiscardAtStart);
fbHoldTimer(   IN := (eState = E_LeakState.TESTING),  PT := tHoldDuration);

// =============================================================================
// 5. Sequence
// =============================================================================
CASE eState OF

    E_LeakState.IDLE:
        bTestComplete      := FALSE;
        bLeakWithinLimit   := FALSE;
        bResultTrustworthy := FALSE;
        rTareMassG         := 0.0;
        rCapturedMassG     := 0.0;
        rLeakRateMlMin     := 0.0;
        rElapsedSec        := 0.0;
        fbSlope(bReset := TRUE);

        IF bStartTestCycle AND NOT bLoopFault THEN
            eState := E_LeakState.SETTLING;
        END_IF

    E_LeakState.SETTLING:
        (* Unpressurised, vessel resting on the cell. Creep decaying. *)
        IF fbSettleTimer.Q THEN
            eState := E_LeakState.TARED;
        END_IF

    E_LeakState.TARED:
        (* Zero captured once, at the end of settling. Then the opening
           minutes of the pressurised hold are discarded so residual creep and
           the thermal transient from pressurisation stay out of the fit. *)
        IF fbDiscardTimer.ET = T#0S THEN
            rTareMassG := rAbsoluteMassG;
        END_IF

        IF fbDiscardTimer.Q THEN
            fbSlope(bReset := TRUE);
            rElapsedSec := 0.0;
            eState      := E_LeakState.TESTING;
        END_IF

    E_LeakState.TESTING:
        (* Elapsed time taken from the timer rather than accumulated by adding
           a nominal cycle time, which drifts against real time. *)
        rElapsedSec := TIME_TO_REAL(fbHoldTimer.ET) / 1000.0;

        IF fbAlarmDebounce.Q THEN
            eState := E_LeakState.ALARM;
        ELSIF fbHoldTimer.Q THEN
            bTestComplete := TRUE;
        END_IF

    E_LeakState.ALARM:
        bTestComplete := TRUE;

    E_LeakState.ABORTED:
        bTestComplete := FALSE;

END_CASE

// =============================================================================
// 6. Captured mass and rate
// =============================================================================
(* Deliberately unclamped. Negative captured mass is real information: the
   vessel is losing water faster than the valve leaks into it, which indicates
   an unsealed vessel or a thermal problem -- not a tight valve. *)
IF eState = E_LeakState.TARED OR eState = E_LeakState.TESTING
   OR eState = E_LeakState.ALARM THEN
    rCapturedMassG := rAbsoluteMassG - rTareMassG;
ELSE
    rCapturedMassG := 0.0;
END_IF

fbSlope(
    bEnable      := (eState = E_LeakState.TESTING),
    bReset       := FALSE,
    rTimeSec     := rElapsedSec,
    rValue       := rCapturedMassG,
    uiWindowSize := GVL_HydroLeak.c_uiSlopeWindowSize
);

rFitR2 := fbSlope.rR2;

IF rFluidDensityGPerMl > 0.0 THEN
    rLeakRateMlMin := fbSlope.rSlopePerMin / rFluidDensityGPerMl;
ELSE
    rLeakRateMlMin := 0.0;
END_IF

// =============================================================================
// 7. Alarm debounce
// =============================================================================
(* The rate must stay over the limit continuously before the state latches.
   A single noisy window must not fail a valve. The window must also be full --
   a slope fitted over three samples is meaningless. *)
fbAlarmDebounce(
    IN := (eState = E_LeakState.TESTING)
          AND fbSlope.bValid
          AND fbSlope.bWindowFull
          AND (rLeakRateMlMin > rActiveThresholdMlMin),
    PT := GVL_HydroLeak.c_tAlarmDebounce
);

// =============================================================================
// 8. Verdict
// =============================================================================
bResultTrustworthy := bTestComplete
                      AND fbSlope.bValid
                      AND fbSlope.bWindowFull
                      AND (rFitR2 >= GVL_HydroLeak.c_rMinR2)
                      AND NOT bLoopFault;

bLeakWithinLimit   := bResultTrustworthy
                      AND (eState <> E_LeakState.ALARM)
                      AND (rLeakRateMlMin <= rActiveThresholdMlMin);

// =============================================================================
// 9. Abort
// =============================================================================
IF bOperatorAbort OR bLoopFault THEN
    IF eState <> E_LeakState.IDLE THEN
        eState := E_LeakState.ABORTED;
    END_IF
END_IF

IF NOT bStartTestCycle THEN
    eState := E_LeakState.IDLE;
END_IF
