# Assumptions and design basis

> All values are **illustrative**. They come from public literature, standards or engineering
> estimates, and are chosen to be mutually consistent, not to represent any specific plant.
> The single numerical source is [`simulink/params.m`](../simulink/params.m). Run
> `params('report')` in MATLAB to reproduce every number in section 2.

## 1. Conventions

| Item | Convention |
|---|---|
| Units in the model | SI: Pa, kg/s, K, W, s |
| Pressures in equations | **Absolute** (bar a). Gauge values (barg) only for set points, ranges and reporting. 1 atm = 1.01325 bar |
| Normal conditions | 0 °C, 1.01325 bar (Nm³) |
| Downstream network | Stiff: constant 0.1 barg (a gas holder / large network is assumed) |
| Gas temperature | Isothermal at the turbine inlet temperature along the header (dry cleaning, insulated mains) |
| Gas source | The furnace delivers a **mass flow** imposed by the blast (the cold-blast blowers are flow-controlled), so ṁ_in(t) is an exogenous disturbance, independent of top pressure |

## 2. Design point (computed, `params('report')`)

### 2.1 Gas properties: blast-furnace gas

| Quantity | Value | Source / rationale |
|---|---|---|
| Composition (vol, dry) | ~50% N₂, 22% CO, 22% CO₂, 4% H₂ | Typical range for modern BFs [1] |
| Molar mass M | 0.030 kg/mol | Weighted average of the above |
| R_s = R/M | **277.1 J/kg/K** | Computed |
| Normal density ρ_N | **1.338 kg/Nm³** | Computed (ideal gas) |
| c_p | 1050 J/kg/K | Mixture of diatomic gases + CO₂ at ~120 °C [2] |
| k = c_p/c_v | **1.359** | Derived as c_p/(c_p − R_s), so the gas model is ideal-gas consistent (literature for BF gas: 1.36–1.39) |

### 2.2 Pressures and flow

| Quantity | Value | Source / rationale |
|---|---|---|
| Top-gas flow | **280 000 Nm³/h = 104.1 kg/s** | ~1500 Nm³/t HM × ~190 t/h: a medium-large BF [1] |
| Top-pressure set point | **1.8 barg = 2.813 bar a** | Modern European BFs run at ~1.5–2.5 barg [1] |
| Gas-cleaning Δp | 0.20 bar at design flow, ∝ ṁ² | Dust catcher + bag filters, engineering estimate |
| ESD + inlet piping Δp | 0.05 bar at design flow, ∝ ṁ² | Large butterfly ESD, fully open |
| Header pressure p_h | **2.613 bar a** | p_top − Δp_clean |
| Turbine inlet p_in | **2.563 bar a** (1.55 barg) | p_h − Δp_ESD. **Not** p_top |
| Turbine outlet p_out | **1.113 bar a** (0.1 barg) | Plant gas network |
| Expansion ratio | **2.30** | p_in / p_out |
| Turbine inlet temperature | 120 °C (TT-101) | Dry cleaning keeps the gas hot and dry. With wet scrubbing it would be ~40–60 °C, saturated, with much lower power |

### 2.3 Power and energy (consistency check)

```
Δh_is  = cp · T_in · (1 − (p_out/p_in)^((k−1)/k))   = 81.6 kJ/kg
P_turb = η_is · ṁ · Δh_is                            = 7.22 MW     (η_is = 0.85)
P_el   = P_turb · η_mech · η_gen                     = 6.86 MW     (0.98 · 0.97 = 0.95)
E_yr   = P_el · 8000 h                               = 54.9 GWh/yr
```

| Quantity | Value | Source / rationale |
|---|---|---|
| η_is (turbine) | 0.85 | Typical for multi-stage axial TRTs [3] |
| η_mech · η_gen | 0.98 · 0.97 ≈ 0.95 | Bearings (direct drive, no gearbox); ~9 MVA synchronous generator |
| Availability | 8000 h/yr | BF campaign, TRT outages for maintenance |
| **Check** | 6.9 MW, 55 GWh/yr | Matches the order of magnitude published for medium-size European TRTs (6–8 MW) ✔ |

The model must **reproduce this point at steady state** (acceptance criterion, verified in phase 3).

## 3. Turbine: Stodola ellipse law

```
ṁ_TRT = K · g(α) · sqrt((p_in² − p_out²) / T_in),     g(α) = α
```

| Quantity | Value | Rationale |
|---|---|---|
| Design vane opening α_des | 0.80 | 20% margin for flow increases before the bypass must open |
| K | 1.1175·10⁻² (SI) | Fitted at the design point |
| Max TRT flow (α = 1, design p) | 130 kg/s = **125%** | Consequence of α_des |
| g(α) linear | simplification | Real stator-vane characteristics are mildly non-linear; linear keeps the linearisation transparent |

The Stodola (cone) law is the standard quasi-steady flow model for multi-stage turbines [3].
A choked-nozzle model would be wrong here: across a multi-stage machine the overall ratio of
2.3 is shared among stages, so the flow still depends on p_out.

## 4. Bypass / septum valves PV-201A/B: ISA-75.01 compressible flow

```
W [kg/h] = N6 · Fp · Kv · f(θ) · Y · sqrt(x · p1[bar] · ρ1)
x = Δp / p1,  limited to x_ch = Fk · xT;   Y = 1 − x/(3 · Fk · xT)   (= 2/3 when choked)
f(θ) = (R^θ − 1)/(R − 1)   (equal percentage, zero at closed)
```

| Quantity | Value | Rationale |
|---|---|---|
| Standard | ISA-75.01.01 / IEC 60534-2-1 [4] | |
| N6 | 27.3 | Kv, kg/h, bar, kg/m³ |
| xT | 0.45 | High-performance butterfly / segment valve near full open |
| Fk = k/1.4 | 0.970 | |
| x at design | **0.574 > x_ch = 0.437 → choked** ✔ | The valve is in choked flow at normal operation. Flow is then ∝ p1 and independent of p2, which makes the trip feedforward inversion simple and robust |
| Capacity | 2 × 60% of design flow at full travel (120% total) | Must absorb 100% at trip, plus margin for slips |
| Kv per valve | **7470 m³/h** | Sized at design header pressure (≈ DN 1000 class butterfly) |
| Rangeability R | 30 | Equal-percentage trim |

## 5. Equivalent gas volume (physical estimate)

V is **estimated from the plant layout, not tuned** to obtain a time constant.

| Section | Volume [m³] | Basis (engineering estimate) |
|---|---|---|
| Furnace top dome (above stock line) | 500 | ~3000 m³ inner-volume furnace |
| Uptakes, downcomer, dirty-gas main | 400 | DN 2000–3000 ducts, ~100 m |
| Dust catcher | 1200 | ~Ø 11 m × 15 m effective |
| Bag filters (dirty + clean side) | 1500 | ~10 vessels × 150 m³ |
| Clean-gas mains to TRT / septum station | 400 | DN 2000, ~120 m |
| **Total V** | **4000** | |

Derived quantities:

| Quantity | Value | Comment |
|---|---|---|
| Gas capacitance C = V/(R_s·T) | 0.0367 kg/Pa | |
| Stored mass at p_h | 9.6 t (≈ 92 s of flow) | |
| Open-loop time constant (vanes frozen) | **τ ≈ 73 s** (single volume); 84 s + 2.6 s (two-volume model) | τ = C / (∂ṁ/∂p_in), ∂ṁ/∂p_in = ṁ·p_in/(p_in² − p_out²) |

**Two-volume model.** The volume is split around the gas-cleaning resistance, so that the top
pressure has its own dynamics (a single lumped volume with an algebraic cleaning Δp made the
top pressure jump instantly with the furnace flow, which is not physical):

| Volume | Content | Value |
|---|---|---|
| V1 (top, measured by PT-100A/B/C) | furnace top + uptakes + dust catcher + dirty side of the filters | 2850 m³ |
| V2 (header, measured by PT-110) | clean side of the filters + clean-gas mains | 1150 m³ |

```
C1 · dp1/dt = ṁ_in − ṁ_c,             C_i = V_i / (R_s · T)
C2 · dp2/dt = ṁ_c − ṁ_TRT − ṁ_BP,     p1 − p2 = k_clean · ṁ_c²
```

Linearised at the design point (vanes frozen), the two time constants are **84 s** (dominant,
the whole gas inventory against the turbine) and **2.6 s** (V1 discharging through the
cleaning resistance into V2). The second one is what the top-pressure controller sees as an
extra lag between the vanes and PT-100.

### 5.1 Back-of-envelope trip estimate (to be confirmed by simulation)

| Case | Unbalanced flow | Δp_top |
|---|---|---|
| No feedforward: PI must "find" the bypass opening (~5 s equivalent) | 104 kg/s × 5 s | ≈ 0.14 bar (8% of 1.8 barg) |
| With feedforward: bypass at FF position in ~1.5 s | 104 kg/s × 1.5 s | ≈ 0.04 bar (2.4%) |
| **Simulation (phase 3)**, feedback only | | **0.214 bar**: the PI needs ≈ 12 s, the HH protection (P1) opens the bypass |
| **Simulation (phase 3)**, FF + tracking | | **0.017 bar** (ESD closing and bypass opening overlap) |

Acceptance target: < ±5% of set point **in barg** = **0.09 bar**.

## 6. Rotor (two modes)

| Quantity | Value | Rationale |
|---|---|---|
| Speed | 3000 rpm | 2-pole generator, 50 Hz, direct drive |
| Generator rating | 9 MVA | P_el / 0.8 power factor |
| Inertia constant H (turbine + generator) | 1.2 s | Typical 1–2 s for this size [5] |
| J = 2·H·S/ω² | **219 kg·m²** | |
| Kinetic energy at 100% speed | 10.8 MJ | |
| Mechanical losses | 2% of P_turb at 100% speed, ∝ ω² | Windage + bearings |

- **CB-101 open:** `J·ω·dω/dt = P_turb − P_loss` (free rotor, run-up, sync, after trip / grid loss).
- **CB-101 closed:** ω = ω_grid (infinite bus), `P_el = (P_turb − P_loss)·η_gen`.

**Load-rejection estimate:** if P_turb decays linearly while XV-101 closes in 0.7 s, the rotor
absorbs ≈ 2.5 MJ, so the speed rises by **≈ 11%**. That is above the 110% overspeed trip:
the ESD closing time, not the trip threshold, limits the peak speed. Scenario 6 quantifies this
(and the extra energy of the gas trapped between the ESD and the turbine).

## 7. Actuators and instruments

| Item | Value | Rationale |
|---|---|---|
| PLC / controller sample time Ts | 100 ms | Typical process PLC task for pressure loops |
| Stator vanes ZY-101 | 1st order τ = 1 s, rate 5 %/s (20 s full stroke); quick close 3 s | Hydraulic vane actuator, slower than the bypass |
| Bypass PV-201A/B, regulating | τ = 0.3 s, rate 10 %/s | Positioner |
| Bypass PV-201A/B, fast opening (XY-201A/B) | 1.5 s full stroke | Solenoid quick-exhaust path |
| ESD XV-101 closing | **0.7 s** (sensitivity 0.5–1.0 s) | Quick-closing butterfly with spring/accumulator |
| PT-100A/B/C | 0–4 barg, τ = 0.2 s, noise σ = 2 mbar | Transmitter + impulse line |
| PV filter (PLC) | first order, 1 s, on the voted top pressure | Limits actuator wear from measurement noise |

## 8. Alarm and trip thresholds

| Tag | Limit | Value | Action |
|---|---|---|---|
| PT-100 (voted) | H / HH | 1.9 / 2.0 barg | Alarm / bypass fully open |
| PSV-100A/B | set | 2.2 barg | Mechanical bleeders (outside PLC) |
| ST-101 | HH | 3300 rpm (110%) | TRT trip |
| VT-101 | H / HH | 80 / 120 µm pk-pk | Alarm / trip |
| PT-102 | L / LL | 1.5 / 1.0 barg | Alarm / trip |
| PDT-103 | L / LL | 30 / 15 mbar | Alarm / trip |
| AT-100 | H / HH | 5 / 10 mg/Nm³ | Start inhibit, alarm / controlled unloading (S1) |

The authoritative list is [`tags.csv`](../tags.csv). The I/O list and C&E are generated from it.

## 9. Disturbances (scenario inputs)

| Disturbance | Shape | Value |
|---|---|---|
| Blast flow step | step | ±10% of design flow |
| Slip | short pulse | +30% for ~5 s (rise/fall ~1 s), engineering estimate |
| Stove changeover (24 h profile) | dip | −5% for ~60 s every ~50 min |
| Slow blast variations (24 h profile) | filtered noise | ±5%, time scale ~10 min |
| Random slips (24 h profile) | Poisson | ~3 per day |
| Measurement noise | white | σ = 2 mbar |

The 24 h profile is generated with a fixed random seed (phase 5).

## References (public literature)

1. M. Geerdes, H. Toxopeus, C. van der Vliet, *Modern Blast Furnace Ironmaking – An Introduction*, IOS Press: gas composition, specific gas volume, top pressure ranges.
2. NIST Chemistry WebBook: heat capacities of N₂, CO, CO₂, H₂.
3. S. L. Dixon, C. A. Hall, *Fluid Mechanics and Thermodynamics of Turbomachinery*, Butterworth-Heinemann: axial turbine efficiency; Stodola cone law (also in standard steam-turbine texts).
4. ANSI/ISA-75.01.01 (IEC 60534-2-1), *Flow equations for sizing control valves*.
5. P. Kundur, *Power System Stability and Control*, McGraw-Hill: inertia constants of generating units.
6. IEC 61511 (functional safety, process sector); API 670 (machinery protection systems): see `safety_note.md`.
