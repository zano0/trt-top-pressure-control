# Functional safety note (educational)

> **This is a didactic example, not a safety assessment.** The SIL values below are
> hypothetical. They are derived from invented, round-number frequencies and probabilities,
> to show the reasoning of IEC 61511 (hazard → required risk reduction → SIL), not to
> classify any real plant. A real assessment needs a HAZOP and a LOPA by a qualified team
> with plant-specific data.

| | |
|---|---|
| Related | [02 Control narrative](02_control_narrative.md) §9 · [04 Cause & Effect](04_cause_and_effect.md) |
| Standards referred to | IEC 61511 (process sector SIS), IEC 61508, API 670 (machinery protection), ISA-84 |

## 1. What is (and is not) a safety function here

| Function | Safety function? | Why |
|---|---|---|
| Trip feedforward of the bypass (PY-201) | **No** (BPCS) | It improves top-pressure performance at trip. If it fails, the PI still acts and the bleeders still protect the furnace |
| Top-pressure control (PIC-100) | **No** (BPCS) | Normal control. Its failure is an *initiating event* for the SIFs below |
| Turbine overspeed trip | **Yes**, SIF-01 | Rotor burst can injure or kill people |
| Seal-gas loss trip | **Yes**, SIF-02 | Leakage of CO-rich gas into the machine hall (toxic) |
| Top pressure HH → bypass fully open | **Candidate**, SIF-03 | Protects the furnace top and gas system. The mechanical bleeders are a separate protection layer |
| Lube-oil LL, vibration HH trips | **No**, machinery protection | Mainly asset protection; handled by the MPS (API 670) |
| Emergency stop HS-101 | Manual, hardwired | Operator-initiated. In a real plant it is wired directly to the trip relays, not only to the PLC |

## 2. Hypothetical SIL determination (LOPA-style)

Target frequencies (illustrative, typical order of magnitude for corporate risk criteria):
fatality 1·10⁻⁴ /yr per scenario; major environmental release 1·10⁻² /yr.

`Required PFD = target frequency / (initiating frequency × product of conditional modifiers × PFD of other IPLs)`

| SIF | Hazard | Initiating event (freq.) | Conditional modifiers | Other IPLs | Required PFD | RRF | Hypothetical SIL |
|---|---|---|---|---|---|---|---|
| SIF-01 Overspeed: ST-101 HH → close XV-101 + vanes | Rotor burst | Grid loss / load rejection, 1 /yr | Occupancy 0.1; probability of fatality 0.5 | none credited (the ESD is the protection) | 2·10⁻³ | 500 | **SIL 2** |
| SIF-02 Seal gas LL: PDT-103 LL → trip | CO exposure | Seal-gas supply failure, 0.5 /yr | Occupancy 0.1; probability of fatality 0.3 | CO detection + ventilation, PFD 0.1 | 6.7·10⁻² | 15 | **SIL 1** |
| SIF-03 Top pressure HH → bypass fully open | Bleeder lift: raw-gas and dust release | Failure of top-pressure control (BPCS), 0.1 /yr | – | – (the bleeder lift *is* the consequence) | 1·10⁻¹ | 10 | **SIL 1** (borderline: could be a BPCS function with procedure) |

Notes:
- The BPCS initiating frequency of 0.1 /yr is the usual lower limit IEC 61511 allows to be
  claimed for a BPCS failure without further justification.
- SIF-01 is the dominant function. The ESD closing time (0.7 s) must be part of its safety
  requirement: from the load-rejection estimate in [assumptions.md](assumptions.md) §6, the
  peak speed rises by ≈ 11 % in that time. The **response time**, not only the PFD, defines
  the function.

## 3. Consequences for the design (what a real project would change)

1. **Independence.** IEC 61511 requires the SIS to be independent of the BPCS to the extent
   claimed in the risk reduction: when a BPCS failure is the initiating event, the SIF and the
   BPCS cannot fail together. Sharing sensors, logic solver or final elements is not
   forbidden in itself. It must be justified by analysis (common-cause failures, effect on the
   claimed PFD and on the initiating-event frequency), and in practice it limits the risk
   reduction that can be claimed. The simplest defensible choice here is to keep the final
   elements separate:
   - SIF-03 acts through the **dedicated solenoids XY-201A/B** (de-energise → valve open),
     not through the positioner signal of PY-201, which belongs to the BPCS;
   - SIF-01 acts through XY-101 / XY-102 (de-energise to trip), not through the vane
     positioner.
2. **Logic solver.** In this project all functions run in one PLC, for simplicity. In a real
   plant, SIF-01 would be in an **API 670 machinery protection system** with three
   dedicated speed probes (2oo3), and SIF-02/03 in a **SIL-rated safety PLC**, separate from
   the TRT control PLC.
3. **Sensors.** SIF-03 would use its own transmitters (or 2oo3 of PT-100A/B/C only if they are
   SIL-capable and not shared with the BPCS loop beyond what IEC 61511 allows).
4. **Proof testing.** Each SIF needs a proof-test interval and procedure (e.g. ESD partial
   stroke test on line, full test at shutdown) consistent with the PFD target.
5. **Bleeders PSV-100A/B** remain the last, mechanical layer. They are not part of any SIF.

## 4. What the project demonstrates and what it does not

- **Demonstrated:** the C&E logic, trip timing, fail-safe states and the separation between
  control (FF, PI) and protection, simulated in closed loop.
- **Not demonstrated:** SIL verification (PFD calculation of the hardware), safety
  lifecycle documentation, certified hardware. These are outside the scope of an educational
  project.
