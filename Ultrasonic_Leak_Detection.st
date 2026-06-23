PROGRAM Ultrasonic_Leak_Detection
VAR
    // --- Hardware Inputs (Mapped to Beckhoff EL3064 / ELM3104) ---
    iRawAnalogInput     AT %I* : INT;   // Raw 4-20mA input from ultrasonic level transmitter
    bStartTestCycle             : BOOL; // Triggered by FAT rig operator to begin leak test

    // --- System Configuration Constants ---
    // Non-contact ultrasonic level transmitter mounted above the open-top
    // leak-collection vessel, facing downward.  The transmitter emits ultrasonic
    // pulses; time-of-flight to the fluid surface is converted to a 4-20mA signal.
    //
    // Wiring convention used here (verify against specific transmitter datasheet):
    //   4mA  → empty vessel  (maximum distance from sensor to vessel floor)
    //   20mA → full vessel   (minimum distance, fluid surface near sensor)
    // This gives a DIRECT relationship: higher current = higher fluid level.
    c_iRawMin           : INT  := 0;       // Raw integer at 4mA  (Beckhoff 16-bit)
    c_iRawMax           : INT  := 32767;   // Raw integer at 20mA (Beckhoff 16-bit)
    c_rSensorRangeMM    : REAL := 300.0;   // Transmitter measurement span (mm), e.g. 0–300mm level
    c_rVesselAreaCm2    : REAL := 19.635;  // Collection vessel internal cross-section (cm²)
                                           // Example: Ø50mm circular vessel → π×(2.5)² ≈ 19.635 cm²
    c_tSettleTime       : TIME := T#3S;    // 3-second deadband: allow ultrasonic reading to stabilise
    c_rNoiseThreshMM    : REAL := 0.5;     // Dead-band below which level change is treated as noise (mm)

    // --- Internal Logic Variables ---
    rLevelMM            : REAL; // Scaled fluid level in the collection vessel (mm)
    rTareLevel          : REAL; // Captured zero-level at start of test (residual fluid baseline)
    bTareComplete       : BOOL; // Flag: system zeroed and ready
    rNetLevelMM         : REAL; // Level rise relative to tare (mm)
    rActiveLeakVolume   : REAL; // Accumulated leak volume (ml)

    // --- Function Blocks ---
    fbSettleTimer       : TON;      // Deadband timer — wait for ultrasonic echo to stabilise
    fbTareTrigger       : R_TRIG;   // Rising edge: capture tare zero once
END_VAR

// ==============================================================================
// 1. Analog Input Scaling (4-20mA → Fluid Level in mm)
// ==============================================================================
// Scale the Beckhoff raw integer to a physical fluid-level reading in mm.
// At 4mA the vessel is empty (level = 0mm); at 20mA level = c_rSensorRangeMM.
IF c_iRawMax > c_iRawMin THEN
    rLevelMM := (INT_TO_REAL(iRawAnalogInput - c_iRawMin) /
                 INT_TO_REAL(c_iRawMax - c_iRawMin)) * c_rSensorRangeMM;
ELSE
    rLevelMM := 0.0;   // Prevent divide-by-zero on misconfigured constants
END_IF

// ==============================================================================
// 2. Echo Stabilisation & Tare Logic
// ==============================================================================
// Ultrasonic readings can be momentarily disturbed by vibration, turbulence, or
// foam on the fluid surface.  The settle timer allows the echo to stabilise
// before the zero-reference (tare) is captured.
fbSettleTimer(IN := bStartTestCycle, PT := c_tSettleTime);

fbTareTrigger(CLK := fbSettleTimer.Q);

IF fbTareTrigger.Q THEN
    rTareLevel    := rLevelMM;
    bTareComplete := TRUE;
END_IF

// Clear all state when the operator ends the test cycle.
IF NOT bStartTestCycle THEN
    bTareComplete     := FALSE;
    rTareLevel        := 0.0;
    rNetLevelMM       := 0.0;
    rActiveLeakVolume := 0.0;
END_IF

// ==============================================================================
// 3. Active Leak Measurement  (level rise → volume)
// ==============================================================================
// Volume (ml) = cross-sectional area (cm²) × level rise (cm)
//             = c_rVesselAreaCm2 × (rNetLevelMM / 10.0)
//
// Unit chain:  [cm²] × [mm / 10 = cm]  →  [cm³]  ≡  [ml]
IF bTareComplete THEN
    rNetLevelMM := rLevelMM - rTareLevel;

    // Apply noise dead-band: ignore sub-threshold level fluctuations
    IF rNetLevelMM < c_rNoiseThreshMM THEN
        rNetLevelMM := 0.0;
    END_IF

    rActiveLeakVolume := c_rVesselAreaCm2 * (rNetLevelMM / 10.0);
ELSE
    rNetLevelMM       := 0.0;
    rActiveLeakVolume := 0.0;   // Output zero while the system is still settling
END_IF

// rActiveLeakVolume [ml] represents the total accumulated hydraulic fluid leak.
// rNetLevelMM [mm] is available as a raw diagnostic / calibration signal.
//
// NOTE — Foam / Turbulence mitigation: for highly turbulent leaks consider
// enabling the transmitter's internal averaging filter (if available) and
// increasing c_tSettleTime to T#5S.  Alternatively, a first-order IIR software
// filter can be applied to rLevelMM before the tare/net calculation.
//
// Log or trend rActiveLeakVolume in TwinCAT Scope / SCADA for Hydro FAT reporting.
