(*
    F_ISO5208LimitMlMin

    Allowable liquid leakage rate for a valve, in mL/min, from its nominal bore
    and ISO 5208 rate class.

    ISO 5208 expresses liquid rates as a coefficient per unit of nominal bore
    in mm3/s. Conversion to mL/min:

        1 mm3/s = 0.001 mL/s = 0.06 mL/min

    !! The coefficients in GVL_HydroLeak are PLACEHOLDERS and this function    !!
    !! therefore returns 0.0 for every class until they are populated from the !!
    !! controlled copy of ISO 5208. Returning zero is deliberate: it fails     !!
    !! every valve rather than passing one against an invented limit. Do not   !!
    !! "fix" that by guessing values.                                          !!

    Rate A is handled separately -- it is bounded by the rig noise floor from
    the Stage 4.1 blank test, not by a bore-scaled coefficient.
*)
FUNCTION F_ISO5208LimitMlMin : REAL
VAR_INPUT
    eClass  : E_ISO5208Class;
    rDN_mm  : REAL;
END_VAR
VAR CONSTANT
    c_rMm3PerSec_To_MlPerMin : REAL := 0.06;
END_VAR
VAR
    rCoeff : REAL;
END_VAR

IF rDN_mm <= 0.0 THEN
    F_ISO5208LimitMlMin := 0.0;
    RETURN;
END_IF

CASE eClass OF
    E_ISO5208Class.RATE_A:
        (* Noise-floor bounded, not bore-scaled. *)
        F_ISO5208LimitMlMin := GVL_HydroLeak.c_rRateA_NoiseFloorMlMin;
        RETURN;

    E_ISO5208Class.RATE_B:
        rCoeff := GVL_HydroLeak.c_rISO5208_RateB;

    E_ISO5208Class.RATE_C:
        rCoeff := GVL_HydroLeak.c_rISO5208_RateC;

    E_ISO5208Class.RATE_D:
        rCoeff := GVL_HydroLeak.c_rISO5208_RateD;
ELSE
    rCoeff := 0.0;
END_CASE

F_ISO5208LimitMlMin := rCoeff * rDN_mm * c_rMm3PerSec_To_MlPerMin;
