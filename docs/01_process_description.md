# 01 – Process description

| Document | 01_process_description |
|---|---|
| Revision | A (phase 1) |
| Related | [P&ID](pid/trt_pid.svg) · [tags.csv](../tags.csv) · [assumptions.md](assumptions.md) |

> Independent educational project. All parameters are illustrative and based on public literature.

## 1. Purpose of the unit

A blast furnace (BF-001) produces top gas at an elevated pressure (here 1.8 barg). After
cleaning, the gas must be let down to the pressure of the plant gas network (0.1 barg), where
it is used as a low-calorific fuel. A **Top-gas Recovery Turbine (TRT)** recovers the
pressure energy that would otherwise be dissipated in the pressure-reducing (septum) valves,
generating about **7 MW** of electricity (≈ 55 GWh/yr) without burning any fuel.

The TRT must be **transparent to the blast furnace**: top pressure is a critical process
variable for the furnace (gas flow distribution through the burden, blast volume, top
equipment), so it must stay at its set point regardless of what the turbine does, including
when the turbine trips.

## 2. Process flow

```
BF-001 top ─► DC-001 dust catcher ─► FLT-001 bag filters ─► clean-gas header ─┬─► XV-101 ─► T-101 TRT ─┐
 (PT-100A/B/C,                           (Δp ≈ 0.2 bar)      (PT-110, TT-101,  │                          ├─► plant gas network
  PSV-100A/B)                                                 AT-100)          └─► PV-201A/B bypass ──────┘    (PT-300)
                                                                                   (septum station)
```

1. **Furnace top (BF-001).** Gas leaves the furnace through the uptakes at ~1.8 barg. Top
   pressure is measured by three transmitters, **PT-100A/B/C**, voted 2oo3. Two mechanical
   **bleeders PSV-100A/B** (set 2.2 barg) are the last line of defence against overpressure;
   they are outside the control system.
2. **Dust catcher (DC-001)** removes the coarse dust by gravity and inertia.
3. **Bag-filter plant (FLT-001)**: dry fine cleaning. Dry cleaning keeps the gas hot (≈ 120 °C)
   and dry, which raises the TRT output compared with a wet scrubber (gas at 40–60 °C,
   saturated). The cleaning plant causes a flow-dependent pressure drop of ≈ 0.2 bar.
4. **Clean-gas header.** Header pressure (PT-110), gas temperature (TT-101) and residual dust
   (AT-100) are measured here. The header splits into two parallel paths:
   - **TRT path:** quick-closing inlet ESD valve **XV-101** (closing time ≈ 0.7 s, limit
     switches ZSO/ZSC-101), then the axial turbine **T-101**. Its **variable stator vanes**
     (actuator ZY-101, position ZT-101, quick-close solenoid XY-102) set the gas flow through
     the machine. The turbine drives the synchronous generator **G-101** (3000 rpm, 9 MVA),
     connected to the grid through breaker **CB-101**.
   - **Bypass / septum path:** two control valves **PV-201A/B**, each sized for 60% of the
     design flow, with positioners (ZT-201A/B) and fast-opening solenoids (XY-201A/B, full
     stroke 1.5 s). Without the TRT they perform the whole pressure let-down. With the TRT
     running they are almost closed and act as the pressure-relief path at trip.
5. **Plant gas network** (PT-300): a large, stiff network held at ≈ 0.1 barg.

Machine auxiliaries relevant to the control system: lube oil (PT-102), shaft seals with
nitrogen seal gas (PDT-103, protecting against CO leakage), speed (ST-101) and vibration
(VT-101) monitoring.

## 3. Design point

| Quantity | Value |
|---|---|
| Gas flow | 280 000 Nm³/h (104 kg/s) |
| Top pressure | 1.8 barg (2.81 bar a) |
| Turbine inlet pressure | 1.55 barg (2.56 bar a) |
| Network pressure | 0.1 barg (1.11 bar a) |
| Expansion ratio | 2.30 |
| Inlet temperature | 120 °C |
| Shaft / electrical power | 7.2 MW / 6.9 MW |
| Vane opening at design | 80% (TRT capacity 125% of design flow) |
| Bypass state at design | closed; choked flow when open (x = 0.57 > x_ch = 0.44) |
| Pressure time constant, open loop | ≈ 73 s (V ≈ 4000 m³) |

Full derivation, sources and sensitivities: [assumptions.md](assumptions.md).

## 4. Operating modes (overview)

| Mode | Description |
|---|---|
| **Bypass operation** | TRT stopped. PV-201A/B control top pressure (PIC-100). This is the furnace's normal state without TRT |
| **Start-up** | Permissives checked, XV-101 opened, rotor run up on speed control (SIC-101) while the bypass holds top pressure |
| **Synchronisation** | Speed matched to the grid, synchro-check (SYN-101), CB-101 closed |
| **Loading** | Flow transferred gradually from the bypass to the turbine. Pressure control passes from the bypass valves to the stator vanes |
| **Running** | Stator vanes control top pressure (split range). Bypass nearly closed |
| **Unloading / shutdown** | Reverse transfer, CB-101 opened, XV-101 closed |
| **Trip** | XV-101 and vanes close fast. Bypass jumps to a **precomputed feedforward position**, then the pressure controller takes over bumplessly |

The detailed loop assignment per mode and all transitions are defined in the control
narrative (`02_control_narrative.md`, phase 2).

## 5. Key control challenge

At trip, ≈ 104 kg/s of gas that was flowing through the turbine must be rerouted through the
bypass within about a second. The header volume buffers only ≈ 92 s of flow, and every second
of unbalanced flow raises the top pressure by ≈ 0.03 bar. A feedback controller alone must first
see the pressure rise before it opens the bypass. The **feedforward** opens it immediately, to
the position that passes the same mass flow, computed by inverting the ISA-75.01 valve
equation at the current header pressure. Demonstrating this quantitatively is the central result
of the project.
