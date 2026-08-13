(*
    PRG_LeakDetection

    Gravimetric micro-leak measurement for hydrostatic valve testing.

    Sequence:
        IDLE      -> operator loads valve and test parameters
        SETTLE    -> catch vessel resting on the cell, creep decaying
        TARE      -> zero captured at the END of settle
        HOLD_WAIT -> pressurised, early window discarded (residual creep)
        MEASURE   -> samples accumulated into the least-squares fit
        RESULT    -> rate compared against the per-test threshold

    Differences from the earlier draft, and why:

    1. Raw input is DINT, not INT. The ELM3148 is a 24-bit converter presenting
       a 32-bit process value; reading it as a 16-bit INT throws away a factor
       of ~200 in resolution and leaves a 20-minute signal spanning about six
       counts.

    2. Scaling endpoints are configurable, not assumed. 0 / 32767 is a 16-bit
       convention. The correct endpoints come from the ESI file and the
       amplifier's calibrated 4 mA / 20 mA points, and must be verified on the
       bench against known masses.

    3. The acceptance threshold is a per-test input, not a constant. Allowable
       leakage under ISO 5208 / API 6D scales with nominal bore and seat type,
       so a compiled-in limit would force a rebuild for every valve size.

    4. Settle time is minutes, not seconds. Three seconds damps suspension
       swing; it does nothing for load cell creep, which decays over minutes
       and mimics a leak exactly.

    5. No clamping of negative values. Clamping a noisy signal at zero rectifies
       it into a positive bias -- an apparent leak on a tight valve -- and hides
       net mass LOSS, which is the signature of evaporation from an unsealed
       catch vessel.

    6. The result is a rate, because that is what the standards specify.

    See docs/measurement-budget.md for the supporting error budget.
*)
PROGRAM PRG_LeakDetection
VAR CONSTANT
    (* --- Raw scaling. VERIFY against the ESI and a known-mass calibration. --- *)
    c_diRawAt4mA      : DINT  := 0;
    c_diRawAt20mA     : DINT  := 1048576;   (* placeholder -- do not trust *)

    (* Creep decays roughly logarithmically; most of it is spent in the first
       few minutes under load. Tare is taken at the end of this period. *)
    c_tSettleTime     : TIME  := T#5M;

    (* Early hold samples are discarded so that residual creep and any
       thermal transient from pressurisation stay out of the fit. *)
    c_tDiscardAtStart : TIME  := T#2M;

    (* Below this, the mass trace is not linear enough to trust as a leak. *)
    c_rMinR2          : REAL  := 0.90;
END_VAR

VAR
    (* --- Hardware --- *)
    diRawAnalogInput  AT %I* : DINT;    (* Beckhoff ELM3148, 4-20 mA *)

    (* --- Per-test inputs, supplied with the valve ID from the HMI/MES --- *)
    bStartTestCycle          : BOOL;
    sValveId                 : STRING(32);
    rCellCapacityGrams       : REAL := 1000.0;  (* rated capacity of the fitted cell *)
    rFluidDensityGPerMl      : REAL := 0.998;   (* water at 20 C *)
    rAllowableRateMlPerMin   : REAL;            (* ISO 5208 / API 6D class for THIS valve *)
    tHoldDuration            : TIME := T#20M;

    (* --- Measurement --- *)
    rAbsoluteMass            : REAL;
    rTareMass                : REAL;
    rCapturedMass            : REAL;    (* may legitimately go negative *)
    rElapsedSec              : REAL;
    rLeakRateMlPerMin        : REAL;

    (* --- Result --- *)
    bTestComplete            : BOOL;
    bLeakWithinLimit         : BOOL;
    bResultTrustworthy       : BOOL;

    (* --- Sequencing --- *)
    eState                   : (IDLE, SETTLE, TARE, HOLD_WAIT, MEASURE, RESULT);
    fbSettleTimer            : TON;
    fbDiscardTimer           : TON;
    fbHoldTimer              : TON;
    fbRate                   : FB_LeakRateEstimator;
    rSpan                    : REAL;
END_VAR

// =============================================================================
// 1. Analogue input scaling (4-20 mA -> grams)
// =============================================================================
rSpan := DINT_TO_REAL(c_diRawAt20mA - c_diRawAt4mA);

IF rSpan <> 0.0 THEN
    rAbsoluteMass := (DINT_TO_REAL(diRawAnalogInput - c_diRawAt4mA) / rSpan)
                     * rCellCapacityGrams;
ELSE
    rAbsoluteMass := 0.0;
END_IF

// =============================================================================
// 2. Sequence
// =============================================================================
(* Timers are serviced before the state logic so that .Q and .ET are current
   within this cycle rather than one scan stale. *)
fbSettleTimer( IN := (eState = SETTLE),    PT := c_tSettleTime);
fbDiscardTimer(IN := (eState = HOLD_WAIT), PT := c_tDiscardAtStart);
fbHoldTimer(   IN := (eState = MEASURE),   PT := tHoldDuration);

CASE eState OF

    IDLE:
        bTestComplete      := FALSE;
        bLeakWithinLimit   := FALSE;
        bResultTrustworthy := FALSE;
        rTareMass          := 0.0;
        rCapturedMass      := 0.0;
        rLeakRateMlPerMin  := 0.0;
        rElapsedSec        := 0.0;
        fbRate(bReset := TRUE);

        IF bStartTestCycle THEN
            eState := SETTLE;
        END_IF

    SETTLE:
        (* Vessel resting on the cell, unpressurised. Let creep decay. *)
        IF fbSettleTimer.Q THEN
            eState := TARE;
        END_IF

    TARE:
        (* Zero is captured at the END of settle, so the creep that has already
           occurred is absorbed into the tare rather than counted as leakage. *)
        rTareMass := rAbsoluteMass;
        eState    := HOLD_WAIT;

    HOLD_WAIT:
        (* Pressurised. Discard the opening minutes of the hold. *)
        IF fbDiscardTimer.Q THEN
            fbRate(bReset := TRUE);
            rElapsedSec := 0.0;
            eState      := MEASURE;
        END_IF

    MEASURE:
        (* Elapsed time is taken from the hold timer rather than accumulated by
           adding a nominal cycle time, which drifts against real time. *)
        rElapsedSec := TIME_TO_REAL(fbHoldTimer.ET) / 1000.0;

        IF fbHoldTimer.Q THEN
            eState := RESULT;
        END_IF

    RESULT:
        bTestComplete := TRUE;

END_CASE

// =============================================================================
// 3. Captured mass and rate
// =============================================================================
(* Deliberately unclamped. Negative captured mass is real information: it means
   the vessel is losing water faster than the valve is leaking into it, which
   indicates an unsealed vessel or a thermal drift problem, not a tight valve. *)
IF eState = HOLD_WAIT OR eState = MEASURE OR eState = RESULT THEN
    rCapturedMass := rAbsoluteMass - rTareMass;
ELSE
    rCapturedMass := 0.0;
END_IF

fbRate(
    bEnable    := (eState = MEASURE),
    bReset     := FALSE,
    rTimeSec   := rElapsedSec,
    rMassGrams := rCapturedMass
);

IF rFluidDensityGPerMl > 0.0 THEN
    rLeakRateMlPerMin := fbRate.rRateGPerMin / rFluidDensityGPerMl;
ELSE
    rLeakRateMlPerMin := 0.0;
END_IF

// =============================================================================
// 4. Verdict
// =============================================================================
(* A verdict is only meaningful if the fit is valid and the mass trace was
   actually linear. A poor R2 means something disturbed the rig -- it is a
   retest, not a pass. *)
bResultTrustworthy := bTestComplete AND fbRate.bValid AND (fbRate.rR2 >= c_rMinR2);
bLeakWithinLimit   := bResultTrustworthy AND (rLeakRateMlPerMin <= rAllowableRateMlPerMin);

// =============================================================================
// 5. Abort
// =============================================================================
IF NOT bStartTestCycle THEN
    eState := IDLE;
END_IF
