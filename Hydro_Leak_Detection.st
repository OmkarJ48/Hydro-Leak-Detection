PROGRAM Hydro_Leak_Detection
VAR
    // --- Hardware Inputs (Mapped to Beckhoff ELM3148) ---
    iRawAnalogInput     AT %I* : INT;   // Raw 4-20mA input from DLS panel (load cell)
    bStartTestCycle             : BOOL; // Triggered by FAT rig operator to begin leak test

    // --- System Configuration Constants (1kg Top-Down Architecture) ---
    c_iRawMin           : INT  := 0;       // Raw integer value at 4mA (Beckhoff specific, often 0)
    c_iRawMax           : INT  := 32767;   // Raw integer value at 20mA (Beckhoff 16-bit)
    c_rSensorCapacity   : REAL := 1000.0;  // 1kg load cell full-scale (in grams)
    c_tSettleTime       : TIME := T#3S;    // 3-second mechanical deadband for suspension swing

    // --- Internal Logic Variables ---
    rAbsoluteMass       : REAL; // Total mass currently hanging on the sensor (grams)
    rTareMass           : REAL; // Captured weight of the empty bottle (~54g)
    bTareComplete       : BOOL; // Flag: system is zeroed and ready
    rActiveLeakMass     : REAL; // Calculated accumulated leak (grams → ml, 1g = 1ml)

    // --- Function Blocks ---
    fbSettleTimer       : TON;      // Deadband timer before tare capture
    fbTareTrigger       : R_TRIG;   // Rising edge: capture tare only once
END_VAR

// ==============================================================================
// 1. Analog Input Scaling (4-20mA → Grams)
// ==============================================================================
// Convert the raw Beckhoff integer into a percentage of full-scale, then
// multiply by the 1000g load cell capacity.
IF c_iRawMax > c_iRawMin THEN
    rAbsoluteMass := (INT_TO_REAL(iRawAnalogInput - c_iRawMin) /
                      INT_TO_REAL(c_iRawMax - c_iRawMin)) * c_rSensorCapacity;
ELSE
    rAbsoluteMass := 0.0;   // Prevent divide-by-zero on misconfigured constants
END_IF

// ==============================================================================
// 2. Mechanical Deadband & Tare Logic
// ==============================================================================
// Allow the hanging bottle to stop swinging before capturing the tare weight.
fbSettleTimer(IN := bStartTestCycle, PT := c_tSettleTime);

// Capture the tare mass exactly once when the settle timer completes.
fbTareTrigger(CLK := fbSettleTimer.Q);

IF fbTareTrigger.Q THEN
    rTareMass     := rAbsoluteMass;
    bTareComplete := TRUE;
END_IF

// Clear all state when the operator ends the test cycle.
IF NOT bStartTestCycle THEN
    bTareComplete    := FALSE;
    rTareMass        := 0.0;
    rActiveLeakMass  := 0.0;
END_IF

// ==============================================================================
// 3. Active Leak Measurement  (1g = 1ml — gravimetric equivalence for water)
// ==============================================================================
// Calculate cumulative leaked volume only after a valid tare has been taken.
IF bTareComplete THEN
    rActiveLeakMass := rAbsoluteMass - rTareMass;

    // Clamp negative readings caused by ambient vibration / sensor noise.
    IF rActiveLeakMass < 0.0 THEN
        rActiveLeakMass := 0.0;
    END_IF
ELSE
    rActiveLeakMass := 0.0;   // Output zero while the system is still settling
END_IF

// rActiveLeakMass [g] directly represents leaked volume [ml] of hydraulic fluid.
// Log or trend this variable in TwinCAT Scope / SCADA for Hydro FAT reporting.
