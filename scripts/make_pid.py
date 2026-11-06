"""Generate the simplified P&ID (ISA-5.1 style) from a single geometry description.

Outputs (docs/pid/):
  trt_pid.svg, trt_pid.png  -- rendered with matplotlib
  trt_pid.drawio            -- editable diagram with the same geometry

Layout rules (Rev B/C):
  * signal lines are orthogonal only and never cross equipment or labels;
  * control functions sit in a band at the top, above the element they act on;
  * every signal has its own lane; parallel lanes are at least 20 px apart;
  * software links that would clutter the drawing are listed in the notes instead
    (interlock commands to trip solenoids are defined in the C&E matrix).

The script fails if a drawn tag is missing from tags.csv, if a signal segment is not
orthogonal, or if two parallel signal segments are closer than MIN_LANE.

Usage:  .venv/bin/python scripts/make_pid.py
"""
from __future__ import annotations

import csv
import html
from itertools import combinations
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Circle, FancyBboxPatch, Polygon, Rectangle, Wedge  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "pid"
REV = "C"
W, H = 1700, 1055         # canvas in px (y grows downward, as in draw.io)
R = 22                    # instrument bubble radius / half side of PLC square
MIN_LANE = 20             # minimum distance between parallel signal lines

PROC = "#1f2a44"          # process lines / equipment
SIG = "#5a6b85"           # signal lines
ACC = "#d9822b"           # accent (trip / ESD / relief)

shapes: list[dict] = []
lines: list[dict] = []


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------
def pipe(*pts, arrow=False):
    lines.append(dict(kind="process", pts=list(pts), arrow=arrow))


def signal(*pts):
    lines.append(dict(kind="signal", pts=list(pts)))


def bubble(tag, x, y, plc=False):
    """ISA-5.1: circle = field instrument; diamond in square = PLC function."""
    shapes.append(dict(kind="bubble", tag=tag, x=x, y=y, plc=plc))


def box(label, x, y, w, h, kind="equipment", rounded=False):
    shapes.append(dict(kind=kind, label=label, x=x, y=y, w=w, h=h, rounded=rounded))


def valve(tag, x, y, actuator="diaphragm", color=PROC, label_dx=24, label_dy=26):
    shapes.append(dict(kind="valve", tag=tag, x=x, y=y, actuator=actuator, color=color,
                       ldx=label_dx, ldy=label_dy))


def text(s, x, y, size=10, weight="normal", ha="center", color=PROC):
    shapes.append(dict(kind="text", s=s, x=x, y=y, size=size, weight=weight, ha=ha, color=color))


# Main coordinates
Y_CTRL = 140              # PLC function row
Y_TRT = 400               # TRT branch
Y_MAIN = 560              # dirty / clean gas line
Y_BPA, Y_BPB = 680, 840   # bypass branches A, B
Y_EXH = 600               # turbine exhaust run
Y_OUT = 760               # outlet to network
X_RISER, X_COLL = 780, 1480
X_XV, X_PV = 850, 1000
X_BPLANE = 955            # bypass command lane
STEM = 40                 # control valve stem length (actuator above body)

# --- Equipment ---------------------------------------------------------------------
box("BF-001\nBlast furnace", 40, 520, 160, 360, rounded=True)
box("DC-001\nDust\ncatcher", 360, 500, 80, 180)
box("FLT-001\nBag-filter\ncleaning", 500, 500, 120, 180)
shapes.append(dict(kind="turbine", tag="T-101", x=1000, y=Y_TRT))          # inlet (narrow) at x, outlet (wide) at x+120
shapes.append(dict(kind="vane_actuator", x=990, y=318, w=140, h=16))
shapes.append(dict(kind="generator", tag="G-101", x=1290, y=Y_TRT))
box("CB-101\n52G", 1370, Y_TRT - 25, 60, 50, kind="breaker")
text("To grid", 1505, Y_TRT, size=10, weight="bold", ha="left")
text("To plant gas network\n(0.1 barg)", 1570, Y_OUT + 45, size=10, weight="bold")
text("Clean-gas\nheader", 795, 525, size=9, ha="left")

# Furnace-top bleeders on the dirty-gas line (ISA relief valve: angle body + spring)
shapes.append(dict(kind="psv", tag="PSV-100A", x=250, y=Y_MAIN))
shapes.append(dict(kind="psv", tag="PSV-100B", x=310, y=Y_MAIN))

# --- Process lines -------------------------------------------------------------------
pipe((200, Y_MAIN), (360, Y_MAIN))
pipe((440, Y_MAIN), (500, Y_MAIN))
pipe((620, Y_MAIN), (X_RISER, Y_MAIN))
pipe((X_RISER, Y_TRT), (X_RISER, Y_BPB))
pipe((X_RISER, Y_TRT), (1000, Y_TRT))
pipe((1120, 448), (1145, 448), (1145, Y_EXH), (X_COLL, Y_EXH))      # exhaust from the wide (outlet) side
pipe((X_RISER, Y_BPA), (X_COLL, Y_BPA))
pipe((X_RISER, Y_BPB), (X_COLL, Y_BPB))
pipe((X_COLL, Y_EXH), (X_COLL, Y_BPB))
pipe((X_COLL, Y_OUT), (1660, Y_OUT), arrow=True)
lines.append(dict(kind="shaft", pts=[(1120, Y_TRT), (1250, Y_TRT)]))
lines.append(dict(kind="electric", pts=[(1330, Y_TRT), (1370, Y_TRT)]))
lines.append(dict(kind="electric", pts=[(1430, Y_TRT), (1495, Y_TRT)], arrow=True))
lines.append(dict(kind="mech", pts=[(1060, 334), (1060, 355)]))      # vane actuator linkage

# --- Valves ------------------------------------------------------------------------------
valve("XV-101", X_XV, Y_TRT, actuator="esd", color=ACC, label_dx=-20, label_dy=30)
valve("PV-201A", X_PV, Y_BPA, label_dx=24, label_dy=20)
valve("PV-201B", X_PV, Y_BPB, label_dx=24, label_dy=20)

# --- Field instruments ---------------------------------------------------------------------
# Furnace top: three transmitters, short taps
for tag, x in (("PT-100A", 70), ("PT-100B", 120), ("PT-100C", 170)):
    bubble(tag, x, 470)
    signal((x, 470 + R), (x, 520))
# Clean-gas header
bubble("PT-110", 700, 500); signal((700, 500 + R), (700, Y_MAIN))
bubble("TT-101", 660, 620); signal((660, 620 - R), (660, Y_MAIN))
bubble("AT-100", 720, 620); signal((720, 620 - R), (720, Y_MAIN))
# ESD valve XV-101: solenoid on top, limit switches on either side (L-shaped taps)
bubble("XY-101", X_XV, 290); signal((X_XV, 290 + R), (X_XV, 366))
bubble("ZSO-101", 790, 300); signal((790, 300 + R), (790, 372), (X_XV - 12, 372))
bubble("ZSC-101", 910, 300); signal((910, 300 + R), (910, 372), (X_XV + 12, 372))
# Stator vanes: positioner, position transmitter, quick-close solenoid on the vane actuator
bubble("ZY-101", 1060, 280); signal((1060, 280 + R), (1060, 318))
bubble("ZT-101", 1005, 280); signal((1005, 280 + R), (1005, 318))
bubble("XY-102", 1115, 280); signal((1115, 280 + R), (1115, 318))
# Machine monitoring
bubble("ST-101", 1180, 280); signal((1180, 280 + R), (1180, Y_TRT))
bubble("VT-101", 1215, 500); signal((1215, 500 - R), (1215, Y_TRT))
bubble("PT-102", 1290, 500); signal((1290, 500 - R), (1290, Y_TRT + 40))
text("lube oil", 1290, 538, size=8, color=SIG)
bubble("PDT-103", 1080, 510); signal((1080, 510 - R), (1080, 453))
text("seal gas", 1080, 546, size=8, color=SIG)
bubble("JT-101", 1350, 300); signal((1350, 300 + R), (1350, Y_TRT))
# Bypass valves: identical arrangement for A and B (B = A shifted by 160 px)
for sfx, yv in (("A", Y_BPA), ("B", Y_BPB)):
    y_act = yv - STEM + 6                     # actuator side connection height
    # command from PY-201 enters the actuator from the left (y_act);
    # XY (fast-opening solenoid) on top of the actuator; ZT reads the stem from the right
    bubble(f"XY-201{sfx}", X_PV, yv - 85); signal((X_PV, yv - 85 + R), (X_PV, yv - STEM))
    bubble(f"ZT-201{sfx}", 1075, yv - 55); signal((1075, yv - 55 + R), (1075, yv - 20), (X_PV, yv - 20))
# Network
bubble("PT-300", 1560, 710); signal((1560, 690 + R), (1560, Y_OUT))

# --- PLC functions (top band) ---------------------------------------------------------------
bubble("PY-100V", 120, Y_CTRL, plc=True)
bubble("PIC-100", 300, Y_CTRL, plc=True)
bubble("PY-100S", 500, Y_CTRL, plc=True)
bubble("PIC-201", 720, Y_CTRL, plc=True)
bubble("PY-201", 940, Y_CTRL, plc=True)
bubble("PY-101", 1060, Y_CTRL, plc=True)
bubble("SIC-101", 1180, Y_CTRL, plc=True)

# 2oo3 inputs: A from the left side, B and C from below (20 px apart)
signal((70, 470 - R), (70, Y_CTRL), (120 - R, Y_CTRL))
signal((120, 470 - R), (120, Y_CTRL + R))
signal((170, 470 - R), (170, 200), (140, 200), (140, Y_CTRL + R))
# Pressure loop chain
signal((120 + R, Y_CTRL), (300 - R, Y_CTRL))
signal((300 + R, Y_CTRL), (500 - R, Y_CTRL))
# Split range: vane share (lane y=65) and bypass share (lane y=90)
signal((490, Y_CTRL - R), (490, 65), (1060, 65), (1060, Y_CTRL - R))
signal((1060, Y_CTRL + R), (1060, 280 - R))
signal((510, Y_CTRL - R), (510, 90), (940, 90), (940, Y_CTRL - R))
# Variant (b) bypass controller output to the bypass selector
signal((720 + R, Y_CTRL), (940 - R, Y_CTRL))
# Header pressure for the feedforward
signal((700, 500 - R), (700, 200), (925, 200), (925, Y_CTRL + R))
# Bypass command lane to PV-201A/B (enters each actuator from the left)
signal((X_BPLANE, Y_CTRL + R), (X_BPLANE, Y_BPB - STEM + 6), (X_PV - 12, Y_BPB - STEM + 6))
signal((X_BPLANE, Y_BPA - STEM + 6), (X_PV - 12, Y_BPA - STEM + 6))
# Speed loop
signal((1180, 280 - R), (1180, Y_CTRL + R))
signal((1180 - R, Y_CTRL), (1060 + R, Y_CTRL))

# --- Legend, notes, title block --------------------------------------------------------------
LY = 925
box("", 40, LY, 560, 118, kind="frame")
text("Legend", 55, LY + 14, size=10, weight="bold", ha="left")
col = [75, 255, 435]
row = [LY + 52, LY + 92]
bubble("FIELD", col[0], row[0]);              text("Field instrument", col[0] + 32, row[0], size=9, ha="left")
bubble("PLC", col[1], row[0], plc=True);      text("PLC function", col[1] + 32, row[0], size=9, ha="left")
shapes.append(dict(kind="psv", tag="", x=col[2] - 4, y=row[0] + 30, legend=True))
text("Relief valve", col[2] + 32, row[0], size=9, ha="left")
lines.append(dict(kind="process", pts=[(col[0] - 22, row[1]), (col[0] + 22, row[1])]))
text("Process line", col[0] + 32, row[1], size=9, ha="left")
lines.append(dict(kind="signal_legend", pts=[(col[1] - 22, row[1]), (col[1] + 22, row[1])]))
text("Electrical signal", col[1] + 32, row[1], size=9, ha="left")
lines.append(dict(kind="process_acc", pts=[(col[2] - 22, row[1]), (col[2] + 22, row[1])]))
text("Trip / ESD / relief", col[2] + 32, row[1], size=9, ha="left")

box("", 620, LY, 600, 118, kind="frame")
text("Notes", 635, LY + 14, size=10, weight="bold", ha="left")
notes = [
    "1. PSV-100A/B: mechanical top bleeders, set 2.2 barg, outside the control system.",
    "2. XY-102 de-energises to dump the vane-actuator hydraulics: stator vanes close fast (trip).",
    "3. Trip solenoids XY-101/102, XY-201A/B and CB-101 trip are driven by interlocks: see C&E.",
    "4. PY-201 selects the bypass output (split range / PIC-201 / trip feedforward with tracking).",
    "   PIC-201 (variant b): PV = PY-100V, SP = PIC-100 SP + offset; software links not drawn.",
    "5. PY-101 selects the vane output: SIC-101 with CB-101 open, PY-100S vane share in loading/running.",
    "6. CB-101 I/O: CLS, TRP, ST; SYN-101 (25), GRID-101, GP-101 (86G). HMI: HS-101 to HS-104.",
]
for i, n in enumerate(notes):
    text(n, 635, LY + 32 + 12 * i, size=7.5, ha="left")

box("", 1240, LY, 420, 118, kind="frame")
text("Simplified P&ID - TRT top-pressure control", 1255, LY + 22, size=11, weight="bold", ha="left")
text("Independent educational project - illustrative only", 1255, LY + 46, size=8.5, ha="left")
text("Not for construction", 1255, LY + 62, size=8.5, ha="left")
text(f"Rev {REV}", 1255, LY + 80, size=8.5, ha="left")


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
def check_tags() -> None:
    with open(ROOT / "tags.csv", newline="") as f:
        known = {row["tag"] for row in csv.DictReader(f)}
    drawn = {s["tag"] for s in shapes if s.get("tag") and s["tag"] not in ("FIELD", "PLC")}
    missing = sorted(drawn - known)
    if missing:
        raise SystemExit(f"Tags drawn on the P&ID but missing from tags.csv: {missing}")
    print(f"P&ID tag check OK: {len(drawn)} tags drawn, all present in tags.csv")


def check_signals() -> None:
    """Orthogonality and minimum spacing between parallel signal segments."""
    segs = []
    for i, ln in enumerate(lines):
        if ln["kind"] != "signal":
            continue
        for (x0, y0), (x1, y1) in zip(ln["pts"], ln["pts"][1:]):
            if x0 != x1 and y0 != y1:
                raise SystemExit(f"Non-orthogonal signal segment {(x0, y0)}-{(x1, y1)}")
            segs.append((i, x0, y0, x1, y1))
    bad = []
    for (i, ax0, ay0, ax1, ay1), (j, bx0, by0, bx1, by1) in combinations(segs, 2):
        if i == j:
            continue
        if ay0 == ay1 and by0 == by1:          # both horizontal
            d = abs(ay0 - by0)
            ov = min(max(ax0, ax1), max(bx0, bx1)) - max(min(ax0, ax1), min(bx0, bx1))
        elif ax0 == ax1 and bx0 == bx1:        # both vertical
            d = abs(ax0 - bx0)
            ov = min(max(ay0, ay1), max(by0, by1)) - max(min(ay0, ay1), min(by0, by1))
        else:
            continue
        if 0 < d < MIN_LANE and ov > 0:
            bad.append(((ax0, ay0, ax1, ay1), (bx0, by0, bx1, by1), d))
    if bad:
        for b in bad:
            print("Lane spacing violation:", b)
        raise SystemExit("Signal lanes closer than MIN_LANE")
    print(f"Signal check OK: {len(segs)} orthogonal segments, lane spacing >= {MIN_LANE} px")


def split_tag(tag: str) -> tuple[str, str]:
    a, _, b = tag.partition("-")
    return a, b


# ---------------------------------------------------------------------------
# Matplotlib renderer (SVG + PNG)
# ---------------------------------------------------------------------------
def turbine_poly(x, y):
    return [(x, y - 30), (x + 120, y - 60), (x + 120, y + 60), (x, y + 30)]


def render_mpl() -> None:
    fig = plt.figure(figsize=(W / 100, H / 100), dpi=100)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, W)
    ax.set_ylim(H, 0)
    ax.axis("off")

    def arrow(p1, p0, color, lw):
        ax.annotate("", xy=p1, xytext=p0, arrowprops=dict(arrowstyle="-|>", color=color, lw=lw))

    for ln in lines:
        xs, ys = zip(*ln["pts"])
        k = ln["kind"]
        if k in ("process", "process_acc"):
            c = PROC if k == "process" else ACC
            ax.plot(xs, ys, color=c, lw=2.2, solid_capstyle="butt", zorder=1)
            if ln.get("arrow"):
                arrow(ln["pts"][-1], ln["pts"][-2], c, 2.2)
        elif k in ("signal", "signal_legend"):
            ax.plot(xs, ys, color=SIG, lw=1.0, ls=(0, (5, 3)), zorder=1)
        elif k == "shaft":
            ax.plot(xs, ys, color=PROC, lw=5, solid_capstyle="butt", zorder=1)
        elif k == "mech":
            ax.plot(xs, ys, color=PROC, lw=1.6, zorder=1)
        elif k == "electric":
            ax.plot(xs, ys, color=PROC, lw=1.6, zorder=1)
            if ln.get("arrow"):
                arrow(ln["pts"][-1], ln["pts"][-2], PROC, 1.6)

    for s in shapes:
        k = s["kind"]
        if k in ("equipment", "breaker"):
            if s.get("rounded"):
                p = FancyBboxPatch((s["x"], s["y"]), s["w"], s["h"], boxstyle="round,pad=0,rounding_size=30",
                                   fc="white", ec=PROC, lw=2, zorder=2)
            else:
                p = Rectangle((s["x"], s["y"]), s["w"], s["h"], fc="white", ec=PROC, lw=2, zorder=2)
            ax.add_patch(p)
            ax.text(s["x"] + s["w"] / 2, s["y"] + s["h"] / 2, s["label"], ha="center", va="center",
                    fontsize=10, color=PROC, zorder=3, linespacing=1.3)
        elif k == "frame":
            ax.add_patch(Rectangle((s["x"], s["y"]), s["w"], s["h"], fc="none", ec=SIG, lw=1, zorder=2))
        elif k == "turbine":
            ax.add_patch(Polygon(turbine_poly(s["x"], s["y"]), closed=True, fc="white", ec=PROC, lw=2, zorder=2))
            ax.text(s["x"] + 62, s["y"], "T-101\nTRT", ha="center", va="center", fontsize=10, color=PROC, zorder=3)
        elif k == "vane_actuator":
            ax.add_patch(Rectangle((s["x"], s["y"]), s["w"], s["h"], fc="white", ec=PROC, lw=1.4, zorder=2))
        elif k == "generator":
            ax.add_patch(Circle((s["x"], s["y"]), 40, fc="white", ec=PROC, lw=2, zorder=2))
            ax.text(s["x"], s["y"], "G-101", ha="center", va="center", fontsize=10, color=PROC, zorder=3)
        elif k == "psv":
            x, y = s["x"], s["y"]
            c = ACC
            cy = y - 26                              # body centre
            if not s.get("legend"):
                ax.plot([x, x], [y, cy + 12], color=c, lw=1.6, zorder=2)            # inlet nozzle
                ax.plot([x + 12, x + 24], [cy, cy], color=c, lw=1.6, zorder=2)      # outlet stub
            ax.add_patch(Polygon([(x - 9, cy + 12), (x + 9, cy + 12), (x, cy)], closed=True, fc="white", ec=c, lw=1.6, zorder=3))
            ax.add_patch(Polygon([(x + 12, cy - 9), (x + 12, cy + 9), (x, cy)], closed=True, fc="white", ec=c, lw=1.6, zorder=3))
            zz_y = [cy, cy - 4, cy - 8, cy - 12, cy - 16, cy - 20]
            zz_x = [x, x - 5, x + 5, x - 5, x + 5, x]
            ax.plot(zz_x, zz_y, color=c, lw=1.2, zorder=3)                         # spring
            if s["tag"]:
                ax.text(x, cy - 26, s["tag"], ha="center", va="bottom", fontsize=7.5, color=c, zorder=3)
        elif k == "valve":
            x, y, c = s["x"], s["y"], s["color"]
            ax.add_patch(Polygon([(x - 18, y - 12), (x - 18, y + 12), (x, y)], closed=True, fc="white", ec=c, lw=2, zorder=2))
            ax.add_patch(Polygon([(x + 18, y - 12), (x + 18, y + 12), (x, y)], closed=True, fc="white", ec=c, lw=2, zorder=2))
            if s["actuator"] == "esd":
                ax.plot([x, x], [y, y - 22], color=c, lw=1.6, zorder=2)
                ax.add_patch(Rectangle((x - 12, y - 34), 24, 12, fc="white", ec=c, lw=1.6, zorder=2))
            else:
                ax.plot([x, x], [y, y - STEM + 12], color=c, lw=1.6, zorder=2)
                ax.add_patch(Wedge((x, y - STEM + 12), 12, 0, 180, fc="white", ec=c, lw=1.6, zorder=2))
            ax.text(x + s["ldx"], y + s["ldy"], s["tag"], ha="left", va="center", fontsize=9,
                    weight="bold", color=c, zorder=3)
        elif k == "bubble":
            x, y = s["x"], s["y"]
            if s["plc"]:
                ax.add_patch(Rectangle((x - R, y - R), 2 * R, 2 * R, fc="white", ec=PROC, lw=1.2, zorder=4))
                ax.add_patch(Polygon([(x, y - R), (x + R, y), (x, y + R), (x - R, y)], closed=True,
                                     fc="white", ec=PROC, lw=1.2, zorder=5))
            else:
                ax.add_patch(Circle((x, y), R, fc="white", ec=PROC, lw=1.2, zorder=5))
            if s["tag"] in ("FIELD", "PLC"):
                continue
            a, b = split_tag(s["tag"])
            fs = 6.5 if s["plc"] else 7.5
            ax.text(x, y - 6, a, ha="center", va="center", fontsize=fs, weight="bold", color=PROC, zorder=6)
            ax.text(x, y + 7, b, ha="center", va="center", fontsize=fs, color=PROC, zorder=6)
        elif k == "text":
            ax.text(s["x"], s["y"], s["s"], ha=s["ha"], va="center", fontsize=s["size"],
                    weight=s["weight"], color=s["color"], zorder=6, linespacing=1.3)

    OUT.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT / "trt_pid.svg")
    fig.savefig(OUT / "trt_pid.png", dpi=150)
    # Drawing only (no legend, notes, title block), for the portfolio PDF
    x0, x1, y0, y1 = 25, W - 10, 45, LY - 12
    fig.set_size_inches((x1 - x0) / 100, (y1 - y0) / 100)
    ax.set_xlim(x0, x1)
    ax.set_ylim(y1, y0)
    fig.savefig(OUT / "trt_pid_drawing.svg")
    plt.close(fig)


# ---------------------------------------------------------------------------
# draw.io renderer (basic shapes only, so the file opens without extra stencils)
# ---------------------------------------------------------------------------
def render_drawio() -> None:
    cells: list[str] = []
    nid = [2]

    def cell(value, style, x, y, w, h):
        cells.append(
            f'<mxCell id="c{nid[0]}" value="{html.escape(value)}" style="{style}" vertex="1" parent="1">'
            f'<mxGeometry x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" as="geometry"/></mxCell>')
        nid[0] += 1

    def edge(pts, style):
        (x0, y0), (x1, y1) = pts[0], pts[-1]
        mids = "".join(f'<mxPoint x="{x}" y="{y}"/>' for x, y in pts[1:-1])
        cells.append(
            f'<mxCell id="c{nid[0]}" style="{style}" edge="1" parent="1"><mxGeometry relative="1" as="geometry">'
            f'<mxPoint x="{x0}" y="{y0}" as="sourcePoint"/><mxPoint x="{x1}" y="{y1}" as="targetPoint"/>'
            f'<Array as="points">{mids}</Array></mxGeometry></mxCell>')
        nid[0] += 1

    base = "edgeStyle=none;html=1;rounded=0;"
    for ln in lines:
        k = ln["kind"]
        end = "endArrow=block;" if ln.get("arrow") else "endArrow=none;"
        if k == "process":
            st = base + f"strokeColor={PROC};strokeWidth=2;" + end
        elif k == "process_acc":
            st = base + f"strokeColor={ACC};strokeWidth=2;" + end
        elif k in ("signal", "signal_legend"):
            st = base + f"strokeColor={SIG};strokeWidth=1;dashed=1;" + end
        elif k == "shaft":
            st = base + f"strokeColor={PROC};strokeWidth=5;" + end
        else:
            st = base + f"strokeColor={PROC};strokeWidth=1.5;" + end
        edge(ln["pts"], st)

    txt = "html=1;whiteSpace=wrap;"
    for s in shapes:
        k = s["kind"]
        if k in ("equipment", "breaker"):
            st = txt + f"fillColor=#ffffff;strokeColor={PROC};strokeWidth=2;" + ("rounded=1;arcSize=15;" if s.get("rounded") else "rounded=0;")
            cell(s["label"].replace("\n", "<br>"), st, s["x"], s["y"], s["w"], s["h"])
        elif k == "frame":
            cell("", f"rounded=0;fillColor=none;strokeColor={SIG};", s["x"], s["y"], s["w"], s["h"])
        elif k == "vane_actuator":
            cell("", f"rounded=0;fillColor=#ffffff;strokeColor={PROC};", s["x"], s["y"], s["w"], s["h"])
        elif k == "turbine":
            cell("T-101<br>TRT", txt + f"shape=trapezoid;direction=south;flipV=1;perimeter=trapezoidPerimeter;size=0.25;fillColor=#ffffff;strokeColor={PROC};strokeWidth=2;",
                 s["x"], s["y"] - 60, 120, 120)
        elif k == "generator":
            cell("G-101", txt + f"ellipse;fillColor=#ffffff;strokeColor={PROC};strokeWidth=2;", s["x"] - 40, s["y"] - 40, 80, 80)
        elif k == "psv":
            x, cy = s["x"], s["y"] - 26
            cell("", f"triangle;direction=north;fillColor=#ffffff;strokeColor={ACC};", x - 9, cy, 18, 12)
            cell("", f"triangle;direction=west;fillColor=#ffffff;strokeColor={ACC};", x, cy - 9, 12, 18)
            if s["tag"]:
                cell(s["tag"], txt + f"text;fontSize=8;fontColor={ACC};align=center;", x - 40, cy - 42, 80, 16)
        elif k == "valve":
            c = s["color"]
            cell("", f"triangle;direction=east;fillColor=#ffffff;strokeColor={c};strokeWidth=2;", s["x"] - 18, s["y"] - 12, 18, 24)
            cell("", f"triangle;direction=west;fillColor=#ffffff;strokeColor={c};strokeWidth=2;", s["x"], s["y"] - 12, 18, 24)
            if s["actuator"] == "esd":
                cell("", f"rounded=0;fillColor=#ffffff;strokeColor={c};", s["x"] - 12, s["y"] - 34, 24, 12)
            else:
                cell("", f"shape=mxgraph.basic.half_circle;flipV=1;fillColor=#ffffff;strokeColor={c};", s["x"] - 12, s["y"] - STEM, 24, 12)
            cell(f"<b>{s['tag']}</b>", txt + f"text;fontColor={c};fontSize=9;align=left;", s["x"] + s["ldx"], s["y"] + s["ldy"] - 10, 80, 20)
        elif k == "bubble":
            x, y = s["x"], s["y"]
            a, b = ("", "") if s["tag"] in ("FIELD", "PLC") else split_tag(s["tag"])
            if s["plc"]:
                cell("", f"rounded=0;fillColor=#ffffff;strokeColor={PROC};", x - R, y - R, 2 * R, 2 * R)
                cell(f"<b>{a}</b><br>{b}", txt + f"rhombus;fillColor=#ffffff;strokeColor={PROC};fontSize=7;", x - R, y - R, 2 * R, 2 * R)
            else:
                cell(f"<b>{a}</b><br>{b}", txt + f"ellipse;fillColor=#ffffff;strokeColor={PROC};fontSize=8;", x - R, y - R, 2 * R, 2 * R)
        elif k == "text":
            align = s["ha"]
            wdt = 600 if align == "left" else 220
            x0 = s["x"] if align == "left" else s["x"] - wdt / 2
            style = txt + f"text;fontSize={s['size']};fontColor={s['color']};align={align};verticalAlign=middle;" + ("fontStyle=1;" if s["weight"] == "bold" else "")
            cell(s["s"].replace("\n", "<br>"), style, x0, s["y"] - 15, wdt, 30)

    xml = ('<mxfile host="make_pid.py"><diagram name="TRT P&amp;ID" id="pid">'
           f'<mxGraphModel dx="{W}" dy="{H}" grid="1" gridSize="10" page="1" pageWidth="{W}" pageHeight="{H}" math="0" shadow="0">'
           '<root><mxCell id="0"/><mxCell id="1" parent="0"/>' + "".join(cells) +
           '</root></mxGraphModel></diagram></mxfile>')
    (OUT / "trt_pid.drawio").write_text(xml, encoding="utf-8")


if __name__ == "__main__":
    check_tags()
    check_signals()
    render_mpl()
    render_drawio()
    print(f"Written Rev {REV}: {OUT/'trt_pid.svg'}, {OUT/'trt_pid.png'}, {OUT/'trt_pid.drawio'}")
