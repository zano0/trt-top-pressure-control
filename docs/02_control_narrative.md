# 02 – Control Narrative: TRT Top-Pressure Control

| | |
|---|---|
| Document no. | TRT-CN-001 |
| Revision | B – updated with phase 3 simulation results |
| Related documents | [01 Process description](01_process_description.md) · [P&ID](pid/trt_pid.svg) · [03 I/O list](03_io_list.md) · [04 Cause & Effect](04_cause_and_effect.md) · [Assumptions](assumptions.md) · [Safety note](safety_note.md) |
| Tag source | [`tags.csv`](../tags.csv) (all tags in this document exist there) |

> Independent educational project. All parameters are illustrative and based on public literature.

### Revision history

| Rev | Description |
|---|---|
| A | First issue: modes, loops, loop assignment per mode, sequences, trips, instrument failure handling |
| B | Phase 3: PIC-100 tuning (§4.2), PV filter, loading transfer feedforward (§6.3), override tracking (§4.5), OP-2/OP-3 closed with simulation results (§11, §12) |

---

## 1. Introduction

### 1.1 Purpose
This document describes how the Top-gas Recovery Turbine (TRT) and its bypass (septum)
valves are controlled. It covers operating modes, control loops, the assignment of
actuators to loops in each mode, start-up and shutdown sequences, trips and interlocks, and
the handling of instrument failures. It is the reference for the PLC software (phase 4), the
simulation model (phase 3) and the virtual commissioning protocol (phase 6).

### 1.2 Scope
- **In scope:** top-pressure control (PIC-100, PIC-201), bypass output selection and trip
  feedforward (PY-201), stator-vane output selection (PY-101), speed control (SIC-101),
  TRT sequence, TRT trips, 2oo3 voting of top pressure (PY-100V).
- **Out of scope:** blast-furnace process control (blast, burden, stoves), gas-cleaning plant
  control, generator excitation and electrical protection (only their interface signals
  are used), machinery protection system (see §9.4), mechanical top bleeders PSV-100A/B.

### 1.3 Control objectives (in order of priority)
1. **Protect people and equipment** (trips, §9).
2. **Keep top pressure at set point** in every mode, including turbine trip. The TRT must be
   transparent to the furnace.
3. **Maximise recovered energy:** pass as much gas as possible through the turbine, i.e. keep
   the bypass closed whenever the vanes have capacity.
4. Minimise actuator wear (no unnecessary valve movement).

### 1.4 Abbreviations

| Term | Meaning |
|---|---|
| BF | Blast furnace |
| CV / MV | Controlled / manipulated variable |
| FF | Feedforward |
| MPS | Machinery protection system (API 670) |
| OOS | Out of service |
| SP / PV / OP | Set point / process value / controller output |
| TRT | Top-gas Recovery Turbine |

### 1.5 Design basis
Design point: 280 000 Nm³/h, top pressure 1.8 barg, turbine inlet 1.55 barg, network
0.1 barg, 120 °C, P_el ≈ 6.9 MW. Vanes at ≈ 80 % at the design point (TRT capacity 125 %).
Bypass PV-201A/B: 2 × 60 %, choked at normal operation. Open-loop pressure time constant
≈ 73 s. Details: [assumptions.md](assumptions.md).

---

## 2. Control system architecture

| Level | Function | Implementation in this project |
|---|---|---|
| Field | Transmitters, positioners, solenoids, limit switches | Simulated plant (Simulink / Python SiL) |
| Machinery protection | Overspeed, vibration (API 670) | Simulated in the PLC for simplicity, see §9.4 |
| TRT control PLC | Loops, sequence, interlocks, voting | IEC 61131-3 Structured Text (OpenPLC), 100 ms task |
| HMI | Operator interface, alarms, trends | Python dashboard over Modbus TCP |
| BF DCS (interface) | Top-pressure SP, TRT status, permissives | Soft signals (open point §12) |

All loops run in a single cyclic task with **Ts = 100 ms**. The open-loop pressure time
constant (≈ 73 s) and the fastest actuator (ESD, 0.7 s) are both slow compared with Ts.

---

## 3. Operating modes and states

### 3.1 State machine (FB_TRT_Sequence)

```
IDLE ─► PRE_START_CHECKS ─► WARM_UP ─► RUN_UP ─► SYNC ─► LOADING ─► RUNNING
                                                                     │
SHUTDOWN ◄─────────────────────────── UNLOADING ◄────────────────────┘

any state except IDLE / SHUTDOWN ── T1/T2 ──► TRIP ── causes cleared + HS-104 ──► RESET ──► IDLE
```

| State | Description | Exit condition |
|---|---|---|
| IDLE | TRT stopped, XV-101 closed, vanes closed. Bypass controls top pressure | HS-102 start command |
| PRE_START_CHECKS | Permissives checked (§3.2) | All permissives true → WARM_UP; any false for 30 s → IDLE with alarm |
| WARM_UP | XV-101 opened (ZSO-101 within 10 s). Vanes open to warm-up position, rotor held at warm-up speed | Warm-up timer elapsed |
| RUN_UP | SIC-101 ramps speed to synchronous speed | ST-101 within ±1 % of 3000 rpm for 5 s |
| SYNC | SIC-101 trims speed for a small positive slip; synchro-check | SYN-101 true → CB-101-CLS pulse; CB-101-ST true → LOADING |
| LOADING | Flow transferred from bypass to turbine at constant top pressure (§6.3) | Bypass ≤ 2 % for 10 s (or vanes at 100 %) → RUNNING |
| RUNNING | Vanes control top pressure (split range); bypass nearly closed | HS-103 stop → UNLOADING; S1 → UNLOADING |
| UNLOADING | Flow transferred from turbine to bypass (§6.4) | Vanes ≤ 5 % and P_el ≤ 0.2 MW |
| SHUTDOWN | CB-101 opened on reverse power, vanes closed, XV-101 closed | ZSC-101 true → IDLE |
| TRIP | Trip actions per C&E (§9) | All trip causes cleared and HS-104 reset |
| RESET | Controllers re-initialised (bypass-only mapping) | → IDLE |

### 3.2 Start permissives

| # | Permissive | Signal |
|---|---|---|
| P1 | Top pressure stable: voted top pressure within ±0.05 bar of SP for 5 min, PIC-100 in AUTO | PY-100V, PIC-100 |
| P2 | At least two healthy top-pressure transmitters | PY-100V |
| P3 | Gas clean: dust < 5 mg/Nm³ | AT-100 |
| P4 | Gas temperature in range 90–150 °C | TT-101 |
| P5 | Lube oil pressure ≥ 1.5 barg | PT-102 |
| P6 | Seal gas Δp ≥ 30 mbar | PDT-103 |
| P7 | Grid available, no generator protection trip | GRID-101, GP-101 |
| P8 | Bypass has capacity: PV-201A/B healthy (ZT-201A/B within 2 % of command), not in manual | ZT-201A/B |
| P9 | No trip cause active, trip reset | C&E |

---

## 4. Loop descriptions

### 4.1 PY-100V – top-pressure 2oo3 voting
- Inputs: PT-100A/B/C. A transmitter is **bad** if its signal is outside 3.8–20.5 mA (NAMUR
  NE 43) or if it deviates from the median by more than **0.05 bar for 2 s** (discrepancy).
- Output (voted top pressure):

| Healthy transmitters | Voted value | Action (C&E) |
|---|---|---|
| 3 | Median | – |
| 2 | Average of the two healthy | Alarm (C12) |
| 1 | The healthy one | Alarm + controlled unloading S1 (C11) |
| 0 | Last good value held | Trip T2: TRT trip, bypass FF, then bypass output frozen in manual, alarm to BF operator (C08) |

- Voted value alarms: H 1.9 / HH 2.0 barg. HH starts group **P1** (bypass fully open, C09).
- A transmitter declared bad remains bad until the operator acknowledges and it is healthy
  for 10 s (no automatic toggling).

### 4.2 PIC-100 – top-pressure controller
- **CV:** voted top pressure (PY-100V). **SP:** 1.8 barg, local or remote from the BF DCS
  (CAS mode), SP rate limit 0.05 bar/min. **Action:** direct (pressure up → OP up → more
  opening of vanes / bypass).
- **Algorithm:** PI, discrete (Ts = 100 ms), positional form, **back-calculation
  anti-windup** with the actuator position actually reached (ZT-101 or ZT-201A/B, or the
  selector output when the actuator is in tracking). Tuning is derived from the linearised
  plant model (two volumes, §5 of assumptions.md) by SIMC rules:

  | Parameter | Value |
  |---|---|
  | Plant gain OP → top pressure | 0.0545 bar/% |
  | Time constants (dominant / second) | 84 s / 2.6 s |
  | PV filter on the voted top pressure | 1.0 s first order |
  | Effective dead time (lags + filter + Ts/2 + half of 2.6 s) | 3.6 s |
  | Desired closed-loop time constant τc | 6 s |
  | **Kp** (SPLIT / BYPASS_ONLY) | **164 / 328 % per bar** |
  | **Ti** | **38 s** |
  | Back-calculation time constant Tt | = Ti |
- **Modes:** MAN, AUTO, CAS, TRACK. TRACK is forced by the sequence and by PY-201 (§4.5). In
  TRACK the integral state is set so that OP equals the tracked value. The return to AUTO is
  therefore bumpless.
- **Output mapping (PY-100S):** two mappings, selected by the sequence:

| Mapping | Used in | OP 0 → 50 % | OP 50 → 100 % |
|---|---|---|---|
| **BYPASS_ONLY** | all states except RUNNING | bypass 0 → 60 % of design flow | bypass 60 → 120 % of design flow (linear over the full OP range) |
| **SPLIT** | RUNNING | vanes α 0 → 100 % | bypass 0 → 120 % of design flow |

  With SPLIT, OP ≈ 40 % at the design point (α = 80 %). The **bypass request is expressed in
  flow (% of design)**, not in valve position. PY-201 converts flow to position with the
  inverse ISA-75.01 characteristic (§4.5), so the loop gain is about the same on both sides of
  the split point. Vanes: 125 % flow over 50 % OP, bypass: 120 % over 50 % OP. This avoids
  re-tuning at the split point despite the equal-percentage trim.
- **Gain scheduling:** in BYPASS_ONLY the actuator gain is 1.2 % flow per % OP, half of
  that in SPLIT (≈ 2.4–2.5). The proportional gain of PIC-100 is therefore doubled in
  BYPASS_ONLY, so that the closed-loop response is the same in both mappings.
- **Mapping change** (SPLIT ↔ BYPASS_ONLY) is bumpless: before switching, the integral state
  is recomputed so that the new mapping produces the actuator positions present at that
  instant.

### 4.3 PIC-201 – bypass controller (variant b, alternative to split range)
- Same CV as PIC-100. SP = PIC-100 SP + **offset Δ = 0.05 bar**.
- In variant (b), PIC-100 drives the vanes only (0–100 % OP → α 0–100 %) and PIC-201 drives
  the bypass. The bypass stays closed as long as top pressure is below SP + Δ.
- Known drawbacks, to be quantified in scenario 7: steady offset of +Δ while the vanes are
  saturated, and possible interaction of two integrators on one CV (mitigated by the offset
  and by tracking PIC-201 to "closed" while it is not needed).
- Variant (a) or (b) is selected by a configuration constant (not an operator switch). Only one
  variant is active at a time.

### 4.4 PY-101 – stator-vane output selector
Selects the source of the vane command ZY-101:

| State | Source |
|---|---|
| IDLE, PRE_START_CHECKS, SHUTDOWN, TRIP, RESET | Forced 0 % (closed) |
| WARM_UP, RUN_UP, SYNC (CB-101 open) | SIC-101 |
| LOADING | Load ramp (§6.3) |
| RUNNING | PIC-100 via PY-100S (SPLIT, vane share) |
| UNLOADING | Unload ramp (§6.4) |

- Rate limit on the selector output: 5 %/s in all automatic sources (actuator capability).
- On every source change the new source is initialised from the present ZT-101 position
  (output tracking), so the vanes do not jump.
- On trip (T1/T2) the output is forced to 0 % and XY-102 dumps the actuator hydraulics. The
  vanes close in 3 s independently of the positioner.

### 4.5 PY-201 – bypass output selector and trip feedforward
**Normal operation.** PY-201 passes the bypass flow request of PY-100S (variant a) or of
PIC-201 (variant b). It converts the request into a position for PV-201A and PV-201B (both
valves receive the same position) by inverting the ISA-75.01 equation at the present
conditions:

```
W_req per valve [kg/h] = (request % · ṁ_des · 3600) / 2
f = W_req / (N6 · Fp · Kv · Y · sqrt(x · p1 · ρ1)),   x = min(Δp/p1, Fk·xT)
θ = ln(1 + f·(R − 1)) / ln(R)        (inverse equal-percentage characteristic)
```
with p1 = PT-110 (header), p2 = PT-300, T = TT-101.

**Trip feedforward (T1/T2).** On the first PLC cycle of a trip:
1. Latch the turbine flow just before the trip, estimated with the Stodola law:
   `ṁ_TRT = K · α · sqrt((p_in² − p_out²)/T_in)`, with α = ZT-101, p_in = PT-110 − Δp_ESD(ṁ),
   p_out = PT-300, T_in = TT-101 (all values from the previous cycle, before the trip
   actions).
2. Required bypass flow = present bypass flow (from ZT-201A/B) + **k_FF · ṁ_TRT**,
   k_FF = 1.0 nominal (sensitivity 0.8–1.2 in phase 3).
3. Convert to position θ_FF with the inverse characteristic above and command PV-201A/B at
   **full positioner speed** (1.5 s full stroke).
4. Put PIC-100 in **TRACK**, switch PY-100S to BYPASS_ONLY and set the integral so that
   PIC-100 OP corresponds to θ_FF (**output tracking**).
5. After **2 s** release PIC-100 to AUTO. The PI corrects the residual error from the FF
   estimate without a bump, because its output already equals the FF value.

Rationale: at trip ≈ 104 kg/s must be rerouted. The pressure rises by ≈ 0.03 bar for every
second of unbalanced flow (header capacity 0.037 kg/Pa). A feedback-only controller must first
see the rise, and then integrate up to the right opening: the expected peak is ≈ 0.14 bar. With
FF the bypass reaches the right opening while the ESD is still closing, so the expected peak is
≈ 0.04 bar, within the 0.09 bar target. The choked bypass makes the FF robust: the valve flow is
proportional to p1, so a rising header pressure automatically increases the relief flow.

**Top pressure HH (P1).** The output is forced to 100 % and XY-201A/B are de-energised
(fully open in 1.5 s). The override is released automatically when the voted pressure falls
below H (1.9 barg). During the override PIC-100 receives the forced output as its
back-calculation reference (**external reset feedback**). Without this, the integrator winds up
against the override and the pressure rises again at release (found in phase 3).

**Loss of top-pressure measurement (T2).** After the FF step the output is **frozen in
manual**. No automatic pressure control is possible without a measurement; the BF operator
is alarmed.

### 4.6 SIC-101 – speed controller
- Active only with **CB-101 open** (WARM_UP, RUN_UP, SYNC). With the breaker closed the speed
  is fixed by the grid. SIC-101 is then kept in TRACK on its present output.
- **CV:** ST-101. **MV:** vanes through PY-101. **SP:** warm-up speed (1000 rpm) during
  WARM_UP, then a ramp of 300 rpm/min to 3000 rpm in RUN_UP. In SYNC: 3000 rpm + 0.1 %
  (positive slip, so the generator picks up load and does not motor on closing).
- PI with anti-windup; tuned on the free-rotor model `J·ω·dω/dt = P_turb − P_loss` in phase 3.

---

## 5. Loop assignment per mode

| State | Vanes (ZY-101 via PY-101) | Bypass (PV-201A/B via PY-201) | PIC-100 mapping | SIC-101 |
|---|---|---|---|---|
| IDLE / PRE_START / WARM_UP¹ | Closed (WARM_UP: SIC-101) | **PIC-100** controls top pressure | BYPASS_ONLY | TRACK (WARM_UP: AUTO) |
| RUN_UP / SYNC | **SIC-101** (speed) | **PIC-100** controls top pressure | BYPASS_ONLY | AUTO |
| LOADING | Load ramp (open) | **PIC-100** closes the bypass while the turbine takes the flow | BYPASS_ONLY | TRACK |
| RUNNING | **PIC-100** (split range, vane share) | Closed; opens only when the vanes saturate | SPLIT | TRACK |
| UNLOADING | Unload ramp (close) | **PIC-100** opens the bypass | BYPASS_ONLY | TRACK |
| SHUTDOWN | Closed | **PIC-100** | BYPASS_ONLY | TRACK |
| TRIP | Forced closed + XY-102 | **FF step + tracking**, then PIC-100 | BYPASS_ONLY | TRACK |

¹ In WARM_UP the vanes are on SIC-101 at warm-up speed.

**Rule:** at any time exactly one controller acts on top pressure (PIC-100, or PIC-201 for the
bypass in variant b). All controllers that are not acting are in TRACK on the position of
the actuator they would drive, so that any transfer is bumpless.

---

## 6. Sequences

Step times are for the real plant. In the simulation they are scaled down where stated in the
scenario definitions.

### 6.1 Start-up (IDLE → RUN_UP)
| Step | Action | Transition |
|---|---|---|
| S1 | HS-102 start. Check permissives P1–P9 | All true |
| S2 | Energise XY-101: open XV-101 | ZSO-101 within 10 s, otherwise abort and alarm |
| S3 | PY-101 → SIC-101. SP = warm-up speed 1000 rpm. Bypass keeps top pressure (PIC-100 compensates the small turbine flow) | Warm-up timer 10 min |
| S4 | Speed ramp 300 rpm/min to 3000 rpm | ST-101 = 3000 ± 30 rpm for 5 s |

Abort during S2–S4 (any permissive lost, or speed not reached within 15 min): normal stop
via SHUTDOWN, no trip.

### 6.2 Synchronisation (SYNC)
1. SIC-101 SP = 3003 rpm (slip +0.1 %).
2. Synchro-check: |Δf| < 0.1 Hz and |Δφ| < 10° (simulated: SYN-101 true after the speed
   condition has held for 3 s).
3. Pulse CB-101-CLS (500 ms). CB-101-ST must be true within 2 s, otherwise abort.
4. SIC-101 → TRACK. PY-101 → load ramp. State → LOADING.

### 6.3 Loading (LOADING)
- Vanes open with a ramp of 0.5 %/s (≈ 160 s from warm-up opening to 80 %).
- PIC-100 (BYPASS_ONLY) holds top pressure and therefore closes the bypass as the turbine
  takes the flow. **The transfer is done by feedback, not by a pre-programmed bypass ramp.**
- **Transfer feedforward:** the bypass flow request is reduced by the increase of the
  estimated turbine flow (Stodola estimate, same as the trip FF) since the start of loading.
  The PI only corrects the estimation error. Phase 3: peak deviation 3.5 mbar with FF, 58 mbar
  with feedback alone (target 20 mbar).
- When the bypass request drops below 2 %, the vane ramp is **held** during the 10 s
  confirmation. Continuing the ramp would make the turbine take more gas than the furnace
  produces, and the pressure would dip.
- When the bypass request is ≤ 2 % for 10 s, or the vanes reach 100 %:
  1. PIC-100 → TRACK; integral recomputed for SPLIT so that OP = α/2 (vane share = present
     vanes, bypass share = 0);
  2. PY-100S → SPLIT; PY-101 → PIC-100;
  3. PIC-100 → AUTO. State → RUNNING.

### 6.4 Normal stop (RUNNING → UNLOADING → SHUTDOWN → IDLE)
1. HS-103 stop (or S1). PIC-100 → TRACK, mapping → BYPASS_ONLY (bumpless re-init), PIC-100
   → AUTO.
2. PY-101 → unload ramp: vanes close at 0.5 %/s. PIC-100 opens the bypass to hold pressure.
3. When vanes ≤ 5 % and JT-101 ≤ 0.2 MW: vanes → 0 %. CB-101 opens on reverse power
   (CB-101-TRP pulse when JT-101 < 0). State → SHUTDOWN.
4. De-energise XY-101: XV-101 closes. ZSC-101 within 5 s → IDLE.

### 6.5 Trip (TRIP)
Actions per C&E group T1 (or T2), all in the first PLC cycle:
1. XY-101 de-energised: XV-101 closes in 0.7 s.
2. XY-102 de-energised, PY-101 → 0 %: vanes close in 3 s.
3. PY-201 FF step + PIC-100 output tracking (§4.5).
4. CB-101: **sequential tripping**. For mechanical trips the breaker opens only after
   ZSC-101 (ESD closed) and reverse power (JT-101 < 0). Opening it first would add a load
   rejection to the trip and drive the rotor into overspeed. For grid loss and generator
   protection (GRID-101, GP-101) the breaker has already been opened by the electrical
   protection, and the overspeed is limited by the ESD closing time (scenario 6).
5. First-out alarm latched; sequence → TRIP.

Reset (HS-104) is accepted only when all trip causes are cleared and XV-101 is closed.

---

## 7. Alarm management
- Alarm limits and priorities: [03_io_list.md – Alarm list](03_io_list.md#alarm-list)
  (generated from `tags.csv`).
- Priorities: **High** for LL/HH and trips, **Medium** for L/H.
- **First-out:** the first trip cause is latched and shown separately, so that consequential
  alarms do not hide the initiating event.
- Alarms are suppressed by state where they are meaningless (e.g. ST-101 L, PT-102 L in IDLE
  with the lube-oil pump stopped). Suppression is by sequence state, never by operator.
- Additional diagnostic alarms (not tag limits): XV-101 not closed 2 s after a trip
  (ZSC-101); positioner deviation |command − ZT| > 5 % for 5 s (ZY-101, PV-201A/B);
  PT-100 discrepancy.

---

## 8. Instrument failure handling

| Signal failed | Detection | Action |
|---|---|---|
| One of PT-100A/B/C | Range check (NE 43) or discrepancy vs median | §4.1 voting table |
| PT-110 (header) | Range check | FF and bypass characterisation use voted p_top − k_clean·ṁ² instead; alarm |
| PT-300 (network) | Range check | Use design value 0.1 barg; alarm |
| TT-101 | Range check | Use last good value (slow variable); alarm; start inhibited |
| ZT-101 (vane position) | Range check or deviation | FF uses the PY-101 command instead of ZT-101; alarm |
| ZT-201A/B | Range check or deviation | Present bypass flow in FF estimated from the command; alarm; start permissive P8 lost |
| ST-101 | Range check | **Trip T1** while CB-101 open (speed is the only overspeed protection in that state). Alarm only when CB-101 is closed (speed fixed by grid) |
| VT-101 | Range check | Alarm (in a real plant handled by the MPS, §9.4) |
| JT-101 | Range check | Reverse-power stop step uses a time delay (10 s after vanes 0 %) instead |

---

## 9. Trips and interlocks

### 9.1 Cause & Effect
The authoritative list of causes and effects is the generated matrix
[04_cause_and_effect.md](04_cause_and_effect.md) / [.xlsx](04_cause_and_effect.xlsx).

| Group | Meaning | Main causes |
|---|---|---|
| T1 | TRT trip | ST-101 HH, VT-101 HH, PT-102 LL, PDT-103 LL, GRID-101 lost, GP-101, HS-101 |
| T2 | TRT trip + bypass frozen in manual | No healthy top-pressure transmitter |
| P1 | Bypass fully open | Voted top pressure HH |
| S1 | Controlled unloading | AT-100 HH, only one healthy PT-100 |

### 9.2 Fail-safe states
| Element | De-energised / signal loss | Rationale |
|---|---|---|
| XV-101 (XY-101) | Closed | Isolate the turbine |
| Vanes (XY-102) | Closed | Stop driving torque |
| PV-201A/B (XY-201A/B) | Fully open | Relieve the furnace top: preferred to an overpressure that would lift the bleeders |
| PV-201A/B positioner (AO loss) | Fail-last | Avoid a pressure disturbance on a single signal failure |

### 9.3 Trip timing requirement
The trip response is limited by the actuators, not the PLC. Detection of a cause and output of
all actions take ≤ 1 PLC cycle (100 ms) plus I/O update. The safety note discusses what would be
implemented in a separate safety system in a real plant.

### 9.4 Machinery protection
Overspeed (ST-101 HH) and vibration (VT-101 HH) are implemented in the process PLC **only
for this project**. In a real plant they belong to a dedicated machinery protection system
(API 670) with its own speed probes and voting, hardwired to the trip solenoids. See
[safety_note.md](safety_note.md).

---

## 10. HMI requirements
- **Overview:** simplified P&ID with live values, valve positions, TRT state, active loop
  per actuator (from the §5 table) and P_el.
- **Faceplates:** PIC-100, PIC-201, SIC-101 (mode, SP, PV, OP, tracking indication).
- **Trend:** voted top pressure with PT-100A/B/C, vanes, bypass, speed, power (10 min and 2 h).
- **Alarms:** list with priority, first-out, acknowledge.
- **Commands:** HS-102 start, HS-103 stop, HS-104 reset, HS-101 emergency stop (with
  confirmation). Operator SP changes for PIC-100 are limited to 1.6–2.0 barg.

---

## 11. Performance targets and phase 3 results

Results from `simulink/run_scenarios.m` ([kpi_table.md](../simulink/results/kpi_table.md)).
Deviation of the true top pressure from the set point, measurement noise σ = 2 mbar included.

| Case | Target | Phase 3 result |
|---|---|---|
| TRT trip at full load, FF + tracking | Peak < 0.09 bar; no bump at release of tracking | **0.017 bar**; release step 0.01 % ✔ |
| TRT trip at full load, feedback only, nominal PI (reference) | – | 0.214 bar, reaches HH (2.0 barg) |
| TRT trip, feedback only, tight PI (SIMC τc = θ, bypass loop tuned on its own) | – | 0.163 bar (PV filter 1 s), 0.125 bar (filter 0.3 s) |
| Blast-flow step ±10 % (RUNNING) | Peak < 0.05 bar; vanes absorb the step | 0.028 bar; bypass never opens ✔ |
| Furnace slip +30 % for 5 s | – | 0.056 bar; vanes reach 100 %, bypass not needed |
| Loading (simplified sequence), transfer FF | Deviation < 0.02 bar | 0.0035 bar ✔ |
| Loading, feedback only (reference) | – | 0.058 bar ✘: the transfer FF is required |
| Mapping / selector changes | No step in any actuator command | Loading → RUNNING: largest step 0.23 % (bypass closing its last 2 %) ✔ |
| Loss of one PT-100 | No visible disturbance | Phase 4/5 (scenario 5) |

**Why a feedforward and not a faster PI.** The comparison gives feedback alone every advantage:
the bypass-only loop is tuned separately, on the faster actuator, with the SIMC "tight" setting
and a lighter PV filter. The best recommended tuning still gives 0.125 bar. Reaching the 0.09 bar
target needs τc = 0.2 θ, where the phase margin falls to 20° and the noise-driven valve travel is
9 %/min. Even then the peak is five times the feedforward result. The limit is structural:
≈ 104 kg/s disappear in 0.7 s, while the loop sees the effect only after its effective dead time
of 2–3.6 s (transmitter, filter, V1–V2 lag, scan). A controller that waits for the measurement
cannot act in time. The feedforward acts on the trip event itself. Full table:
[kpi_table.md](../simulink/results/kpi_table.md#trip-how-far-can-feedback-alone-go).

Trip sensitivity (peak rise, FF + tracking): 7–27 mbar for ESD closing times 0.5–1.0 s and
bypass full-stroke times 1.0–2.0 s. The bypass stroke time matters more than the ESD time. The
feedforward gain is optimal at k_FF = 1.0, and ±20 % error raises the peak to ≈ 50 mbar,
still within the target.

## 12. Open points

| # | Item |
|---|---|
| OP-1 | Interface with the BF DCS: remote SP, TRT status, hardwired trip signal to BF, permission to start from the BF operator. Real projects agree this in an interface document (scope split TRT supplier / plant DCS) |
| OP-2 | ~~PIC-100 tuning~~ closed in Rev B (§4.2). SIC-101 tuning: phase 4 |
| OP-3 | ~~k_FF and tracking time~~ closed in Rev B: k_FF = 1.0, tracking 2 s (no bump at release, §11) |
| OP-4 | Whether PV-201A/B should open in sequence (A then B) for better low-flow resolution, instead of in parallel |
