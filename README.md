# Hydro Leak Detection

Automated capture and quantification of micro-leaks during hydrostatic (body and
seat) testing of valves, replacing the manual "count the drops" method with a
continuous gravimetric measurement that can be logged, trended and audited.

Target sensitivity is a leak rate on the order of **0.01 mL/min**, which for
water is **10 mg/min** of captured mass.

---

## Status

Feasibility and instrument-selection stage. No production code yet. This
repository currently holds vendor documentation, quotations and the measurement
analysis that drives the hardware decision.

## Repository layout

| Path | Contents |
|---|---|
| `docs/measurement-budget.md` | Error budget for the gravimetric method — what actually limits sensitivity, with numbers taken from the quoted hardware |
| `docs/hardware-options.md` | Side-by-side comparison of the quoted sensing options |
| `src/plc/` | CODESYS Structured Text reference implementation |
| `docs/reference/` | Superseded drafts kept for provenance |
| `datasheets/` | Vendor datasheets (see *Document handling* below) |
| `quotations/` | Supplier quotations |
| `drawings/` | Rig assembly and panel drawings |
| `tools/` | Analysis scripts |

Four files remain at the repository root pending a removal decision: the three
API standards, and `Load Cell 2 Kg Datasheet.pdf`, which is a saved HTML error
page rather than a PDF and needs re-downloading.

## Measurement principle

Fluid escaping past the seat is collected in a catch vessel resting on a
compression load cell. Leak **rate** is the slope of captured mass against time
over the pressurised hold, not the difference between two instantaneous
readings. Fitting a slope is what makes the method work: it cancels any constant
offset — tare error, cell zero-balance, the mass of the vessel itself — and
leaves only drift *within* the hold window as error.

For water, 1 g of captured mass ≈ 1 mL of leaked volume (0.998 g/mL at 20 °C).
If the test fluid is inhibited water or another medium, its density must be
entered per test.

## The three numbers that decide feasibility

1. **Load cell rated capacity** — drift and creep specs are quoted as a
   percentage of rated capacity or rated load, so absolute error scales directly
   with the capacity you buy. Sizing the catch vessel so the cell never sees
   more than it must is the cheapest sensitivity you will ever get.
2. **Pressurised hold duration** — signal accumulates linearly with time while
   random noise averages down. A 60-minute hold is far easier than a 10-minute
   one.
3. **Catch vessel temperature and whether it is sealed** — see
   `docs/measurement-budget.md`. Evaporation from an open vessel is the same
   order of magnitude as the leak being measured, and it biases results towards
   *passing* a leaking valve.

## Acceptance thresholds

Allowable leakage rates under ISO 5208 / API 6D scale with nominal bore and seat
type. The threshold is therefore **a per-test input supplied with the valve
ID**, never a compile-time constant — otherwise every valve size needs a
rebuild. See `src/plc/` for how this is parameterised.

## Applicable standards

API 6A, API 6D and API 17D govern the test procedure; ISO 5208 defines the
leakage rate classes. Copies are *not* redistributed in this repository — see
below.

## Document handling

API standards are licensed documents and are not committed here. Obtain them
through the organisation's subscription. Vendor datasheets and quotations are
retained because they are the source of the numbers in `docs/`.

## Development

Analysis tooling is Python:

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

Work happens on feature branches; `Sub-main` is the integration branch.
