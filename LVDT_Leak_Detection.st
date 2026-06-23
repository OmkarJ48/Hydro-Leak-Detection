PROGRAM LVDT_Leak_Detection
VAR
    // --- Hardware Inputs (Mapped to Beckhoff EL3064 / ELM3104) ---
    iRawAnalogInput     AT %I* : INT;   // Raw 4-20mA input from LVDT signal conditioner
    bStartTestCycle             : BOOL; // Triggered by FAT rig operator to begin leak test

    // --- System Configuration Constants ---
    // LVDT (Linear Variable Differential Transformer) mounted vertically above
    // the leak-collection vessel. The ferromagnetic core is attached to a float
    // that rises as fluid accumulates, producing an upward displacement signal.
    c_iRawMin           : INT  := 0;       // Raw integer value at 4mA  (Beckhoff 16-bit)
    c_iRawMax           : INT  := 32767;   // Raw integer value at 20mA (Beckhoff 16-bit)
    c_rLVDTFullStroke   : REAL := 50.0;    // LVDT full mechanical stroke (mm), e.g. ±25mm = 50mm total
    c_rVesselAreaCm2    : REAL := 19.635;  // Collection vessel internal cross-section (cm²)
                                           // Example: Ø50mm circular vessel → π×(2.5)² ≈ 19.635 cm²
    c_tSettleTime       : TIME := T#3S;    // 3-second deadband: float stabilisation after placement

    // --- Internal Logic Variables ---
    rDisplacementMM     : REAL; // Scaled LVDT displacement from zero reference (mm)
    rTareDisplacement   : REAL; // Captured zero-level displacement (float at rest, empty vessel)
    bTareComplete       : BOOL; // Flag: system zeroed and ready for measurement
    rNetDisplacementMM  : REAL; // Displacement relative to tare position (mm of level rise)
    rActiveLeakVolume   : REAL; // Accumulated leak volume in millilitres

    // --- Function Blocks ---
    fbSettleTimer       : TON;      // Deadband timer — wait for float to stabilise
    fbTareTrigger       : R_TRIG;   // Rising edge: capture tare zero once
END_VAR

// ==============================================================================
// 1. Analog Input Scaling (4-20mA → Displacement in mm)
// ==============================================================================
// The LVDT conditioner outputs 4mA at minimum core displacement (float at
// bottom / vessel empty) and 20mA at maximum upward displacement (vessel full).
// Scale the raw Beckhoff integer to a physical displacement in millimetres.
IF c_iRawMax > c_iRawMin THEN
    rDisplacementMM := (INT_TO_REAL(iRawAnalogInput - c_iRawMin) /
                        INT_TO_REAL(c_iRawMax - c_iRawMin)) * c_rLVDTFullStroke;
ELSE
    rDisplacementMM := 0.0;   // Prevent divide-by-zero on misconfigured constants
END_IF

// ==============================================================================
// 2. Float Stabilisation & Tare Logic
// ==============================================================================
// Wait for the collection vessel float to settle before capturing the zero
// reference.  Any residual fluid from a previous test causes a non-zero tare
// which is correctly zeroed out by this logic.
fbSettleTimer(IN := bStartTestCycle, PT := c_tSettleTime);

fbTareTrigger(CLK := fbSettleTimer.Q);

IF fbTareTrigger.Q THEN
    rTareDisplacement := rDisplacementMM;
    bTareComplete     := TRUE;
END_IF

// Clear all state when the operator ends the test cycle.
IF NOT bStartTestCycle THEN
    bTareComplete      := FALSE;
    rTareDisplacement  := 0.0;
    rNetDisplacementMM := 0.0;
    rActiveLeakVolume  := 0.0;
END_IF

// ==============================================================================
// 3. Active Leak Measurement  (displacement → volume)
// ==============================================================================
// Volume (ml) = cross-sectional area (cm²) × level rise (cm)
//             = c_rVesselAreaCm2 × (rNetDisplacementMM / 10.0)
//
// Unit chain:  [cm²] × [mm / 10  = cm]  →  [cm³]  ≡  [ml]
IF bTareComplete THEN
    rNetDisplacementMM := rDisplacementMM - rTareDisplacement;

    // Clamp negative values: LVDT noise or minor float oscillation
    IF rNetDisplacementMM < 0.0 THEN
        rNetDisplacementMM := 0.0;
    END_IF

    rActiveLeakVolume := c_rVesselAreaCm2 * (rNetDisplacementMM / 10.0);
ELSE
    rNetDisplacementMM := 0.0;
    rActiveLeakVolume  := 0.0;   // Output zero while the system is still settling
END_IF

// rActiveLeakVolume [ml] represents the total accumulated hydraulic fluid leak.
// rNetDisplacementMM [mm] is available as a raw diagnostic / calibration signal.
// Log or trend these variables in TwinCAT Scope / SCADA for Hydro FAT reporting.
