"""Generate the I/O list, alarm list and Cause & Effect matrix from tags.csv.

Outputs (docs/):
  03_io_list.xlsx  (sheets: I/O list, Software tags, Alarm list, I/O summary)
  03_io_list.csv   (hardwired I/O only)
  03_io_list.md    (readable on GitHub)
  04_cause_and_effect.xlsx / .csv / .md

tags.csv is the single source of truth:
  * io_type AI/AO/DI/DO -> hardwired I/O, channels and Modbus addresses allocated here;
  * alarm_LL/L/H/HH     -> alarm list;
  * ce_cause  "<group>:<limit>"            e.g. "T1:HH", "T1:0"  -> C&E rows;
  * ce_effect "<groups>=<action>;..."      e.g. "T1,T2=..."     -> C&E columns.
Degraded-voting causes of the 2oo3 top-pressure measurement are logic states, not tags,
and are defined below (VOTING_CAUSES). Sequence and alarm effects are defined in FIXED_EFFECTS.

Usage:  .venv/bin/python scripts/make_docs.py
"""
from __future__ import annotations

import math
from pathlib import Path

import pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
REV = "A"

MODULE_CH = {"AI": 8, "AO": 4, "DI": 16, "DO": 16}   # channels per I/O module
MIN_SPARE = 0.20                                     # spare capacity per signal type
RAW_SPAN = (0, 27648)                                # 4-20 mA -> raw counts (PLC-neutral convention)
MODBUS = {"AI": "%IW", "AO": "%QW", "DI": "%IX", "DO": "%QX"}

GROUPS = {
    "T1": "TRT trip",
    "T2": "TRT trip + bypass output frozen in manual (loss of top-pressure measurement)",
    "P1": "Top pressure high-high: bypass fully open",
    "S1": "Controlled unloading of the TRT",
    "A": "Alarm only",
}

# Logic-state causes (2oo3 voting of PT-100A/B/C, function PY-100V)
VOTING_CAUSES = [
    ("PY-100V", "One transmitter deviates > 0.05 bar from median (2 healthy left: average)", "A"),
    ("PY-100V", "Only one healthy transmitter left", "S1"),
    ("PY-100V", "No healthy transmitter left", "T2"),
]

# Effects that are functions, not tags: (name, description, groups)
FIXED_EFFECTS = [
    ("FB_TRT_Sequence", "Sequence to TRIP (reset required)", {"T1", "T2"}),
    ("FB_TRT_Sequence", "Sequence to UNLOADING", {"S1"}),
    ("HMI", "Alarm + first-out indication", {"T1", "T2", "P1", "S1", "A"}),
]

EFFECT_ORDER = ["XY-101", "XY-102", "PY-101", "CB-101-TRP", "PY-201", "XY-201A", "XY-201B",
                "FB_TRT_Sequence", "HMI"]

LIMIT_TEXT = {"HH": "high-high", "LL": "low-low", "H": "high", "L": "low", "1": "active", "0": "lost"}


# ---------------------------------------------------------------------------
def load_tags() -> pd.DataFrame:
    t = pd.read_csv(ROOT / "tags.csv", dtype=str).fillna("")
    dup = t["tag"][t["tag"].duplicated()].tolist()
    if dup:
        raise SystemExit(f"Duplicate tags in tags.csv: {dup}")
    return t


def num(s: str) -> float | None:
    return float(s) if s not in ("", None) else None


# ---------------------------------------------------------------------------
# I/O list
# ---------------------------------------------------------------------------
def build_io(t: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    io = t[t["io_type"].isin(["AI", "AO", "DI", "DO"])].copy()
    order = {"AI": 0, "AO": 1, "DI": 2, "DO": 3}
    io["_o"] = io["io_type"].map(order)
    io = io.sort_values(["_o", "tag"], kind="stable").drop(columns="_o")

    rows, summary = [], []
    for typ in ["AI", "AO", "DI", "DO"]:
        sub = io[io["io_type"] == typ]
        n = len(sub)
        per = MODULE_CH[typ]
        modules = max(1, math.ceil(n * (1 + MIN_SPARE) / per))
        summary.append(dict(type=typ, used=n, modules=modules, channels=modules * per,
                            spare=modules * per - n, spare_pct=round(100 * (modules * per - n) / (modules * per))))
        for i, (_, r) in enumerate(sub.iterrows()):
            mod, ch = divmod(i, per)
            if typ in ("AI", "AO"):
                addr = f"{MODBUS[typ]}{i}"
                raw = f"{RAW_SPAN[0]}-{RAW_SPAN[1]}"
            else:
                addr = f"{MODBUS[typ]}{i // 8}.{i % 8}"
                raw = ""
            rows.append({
                "Tag": r["tag"], "Description": r["description"], "I/O type": typ,
                "Signal": r["signal"], "Range min": r["range_min"], "Range max": r["range_max"],
                "Unit": r["unit"], "Raw counts": raw,
                "LL": r["alarm_LL"], "L": r["alarm_L"], "H": r["alarm_H"], "HH": r["alarm_HH"],
                "Fail-safe": r["fail_safe"], "C&E": "yes" if (r["ce_cause"] or r["ce_effect"]) else "",
                "PLC variable": r["plc_name"], "Module": f"{typ}{mod + 1:02d}", "Channel": ch,
                "Modbus (OpenPLC)": addr, "Notes": r["notes"],
            })
    return pd.DataFrame(rows), pd.DataFrame(summary)


def build_soft(t: pd.DataFrame) -> pd.DataFrame:
    s = t[(t["category"] == "soft") | (t["io_type"] == "soft")]
    return s[["tag", "description", "range_min", "range_max", "unit", "plc_name", "notes"]].rename(columns={
        "tag": "Tag", "description": "Description", "range_min": "Range min", "range_max": "Range max",
        "unit": "Unit", "plc_name": "PLC variable", "notes": "Notes"})


def build_alarms(t: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for _, r in t.iterrows():
        trip_lim = r["ce_cause"].split(":")[1] if r["ce_cause"] else ""
        grp = r["ce_cause"].split(":")[0] if r["ce_cause"] else ""
        for lim in ["LL", "L", "H", "HH"]:
            v = r[f"alarm_{lim}"]
            if not v:
                continue
            is_trip = lim == trip_lim
            action = GROUPS[grp] if is_trip else ("Operator action" if lim in ("L", "H") else "Operator action, high priority")
            rows.append({"Tag": r["tag"], "Description": r["description"], "Limit": lim,
                         "Value": v, "Unit": r["unit"],
                         "Priority": "High" if lim in ("LL", "HH") else "Medium",
                         "Action": action, "C&E group": grp if is_trip else ""})
    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# Cause & Effect
# ---------------------------------------------------------------------------
def build_ce(t: pd.DataFrame):
    tagdesc = dict(zip(t["tag"], t["description"]))
    causes = []
    for _, r in t[t["ce_cause"] != ""].iterrows():
        grp, lim = r["ce_cause"].split(":")
        if grp not in GROUPS:
            raise SystemExit(f"Unknown C&E group {grp} for {r['tag']}")
        if lim in ("HH", "LL", "H", "L"):
            val = r[f"alarm_{lim}"]
            if not val:
                raise SystemExit(f"{r['tag']}: C&E limit {lim} has no value in tags.csv")
            cond = f"{LIMIT_TEXT[lim]} ({'>' if lim.startswith('H') else '<'} {val} {r['unit']})"
        else:
            cond = LIMIT_TEXT[lim]
        causes.append(dict(tag=r["tag"], text=f"{r['description']}: {cond}", group=grp))
    for tag, text, grp in VOTING_CAUSES:
        if tag not in tagdesc:
            raise SystemExit(f"Voting cause refers to unknown tag {tag}")
        causes.append(dict(tag=tag, text=text, group=grp))
    order = {"T1": 0, "T2": 1, "P1": 2, "S1": 3, "A": 4}
    causes.sort(key=lambda c: order[c["group"]])

    effects = []
    for _, r in t[t["ce_effect"] != ""].iterrows():
        for part in r["ce_effect"].split(";"):
            grps, action = part.split("=", 1)
            effects.append(dict(tag=r["tag"], text=action.strip(), groups=set(grps.split(","))))
    for name, text, grps in FIXED_EFFECTS:
        effects.append(dict(tag=name, text=text, groups=grps))
    # column order follows the physical trip sequence, not the order in tags.csv
    rank = {tag: i for i, tag in enumerate(EFFECT_ORDER)}
    effects.sort(key=lambda e: rank.get(e["tag"], len(rank)))

    matrix = []
    for c in causes:
        row = []
        for e in effects:
            mark = "X" if c["group"] in e["groups"] else ""
            # grid loss / generator protection: breaker already opened by electrical protection
            if mark and e["tag"] == "CB-101-TRP" and c["tag"] in ("GRID-101", "GP-101"):
                mark = "(X)"
            row.append(mark)
        matrix.append(row)
    return causes, effects, matrix


# ---------------------------------------------------------------------------
# Writers
# ---------------------------------------------------------------------------
HDR_FILL = PatternFill("solid", fgColor="1F2A44")
HDR_FONT = Font(color="FFFFFF", bold=True)
ACC_FILL = PatternFill("solid", fgColor="FBE3CC")
THIN = Side(style="thin", color="B0B7C3")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)


def title_block(ws, title: str, ncols: int) -> int:
    ws.cell(1, 1, title).font = Font(bold=True, size=14, color="1F2A44")
    ws.cell(2, 1, f"Rev {REV} - generated from tags.csv - independent educational project, illustrative only").font = Font(italic=True, color="5A6B85")
    return 4


def write_df(ws, df: pd.DataFrame, start_row: int, widths: dict | None = None) -> None:
    for j, col in enumerate(df.columns, 1):
        c = ws.cell(start_row, j, col)
        c.fill, c.font, c.border = HDR_FILL, HDR_FONT, BORDER
        c.alignment = Alignment(wrap_text=True, vertical="center")
    for i, row in enumerate(df.itertuples(index=False), start_row + 1):
        for j, v in enumerate(row, 1):
            c = ws.cell(i, j, v if v != "" else None)
            c.border = BORDER
            c.alignment = Alignment(wrap_text=True, vertical="top")
    ws.freeze_panes = ws.cell(start_row + 1, 2)
    ws.auto_filter.ref = f"A{start_row}:{get_column_letter(len(df.columns))}{start_row + len(df)}"
    for j, col in enumerate(df.columns, 1):
        w = (widths or {}).get(col) or min(60, max(8, int(max([len(str(col))] + [len(str(x)) for x in df[col]]) * 0.9)))
        ws.column_dimensions[get_column_letter(j)].width = w


def md_table(df: pd.DataFrame) -> str:
    cols = list(df.columns)
    out = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for row in df.itertuples(index=False):
        out.append("| " + " | ".join(str(v).replace("|", "/") for v in row) + " |")
    return "\n".join(out)


def write_io(io, soft, alarms, summary) -> None:
    wb = Workbook()
    ws = wb.active
    ws.title = "IO list"
    r0 = title_block(ws, "03 - I/O list - TRT top-pressure control", len(io.columns))
    write_df(ws, io, r0, widths={"Description": 42, "Notes": 50})
    for name, df, w in (("Software tags", soft, {"Description": 42, "Notes": 60}),
                        ("Alarm list", alarms, {"Description": 42, "Action": 50}),
                        ("IO summary", summary, None)):
        s = wb.create_sheet(name)
        write_df(s, df, title_block(s, f"03 - {name}", len(df.columns)), widths=w)
    wb.save(DOCS / "03_io_list.xlsx")
    io.to_csv(DOCS / "03_io_list.csv", index=False)

    cols = ["Tag", "Description", "I/O type", "Signal", "Range min", "Range max", "Unit",
            "LL", "L", "H", "HH", "Module", "Channel", "Modbus (OpenPLC)"]
    md = [f"# 03 – I/O list (Rev {REV})", "",
          "> Generated by `scripts/make_docs.py` from `tags.csv`. Full version with all columns: "
          "[03_io_list.xlsx](03_io_list.xlsx). Independent educational project, illustrative only.", "",
          "## Hardwired I/O", "", md_table(io[cols]), "",
          f"AI/AO scaling: 4–20 mA ↔ raw counts {RAW_SPAN[0]}–{RAW_SPAN[1]} (scaled in `FB_AI_Scale` / `FB_AO_Scale`). "
          "Modbus addresses refer to the OpenPLC Software-in-the-Loop mapping.", "",
          "## I/O summary (≥ 20 % spare per type)", "", md_table(summary), "",
          "## Software tags", "", md_table(soft), "",
          "## Alarm list", "", md_table(alarms), ""]
    (DOCS / "03_io_list.md").write_text("\n".join(md), encoding="utf-8")


def write_ce(causes, effects, matrix) -> None:
    wb = Workbook()
    ws = wb.active
    ws.title = "C&E"
    title_block(ws, "04 - Cause & Effect matrix - TRT top-pressure control", 0)
    hr = 4
    heads = ["#", "Cause tag", "Cause", "Group"]
    for j, h in enumerate(heads, 1):
        c = ws.cell(hr + 1, j, h)
        c.fill, c.font, c.border = HDR_FILL, HDR_FONT, BORDER
    for k, e in enumerate(effects):
        j = len(heads) + 1 + k
        c1 = ws.cell(hr, j, e["tag"])
        c1.fill, c1.font, c1.border = HDR_FILL, HDR_FONT, BORDER
        c1.alignment = Alignment(horizontal="center")
        c2 = ws.cell(hr + 1, j, e["text"])
        c2.fill, c2.font, c2.border = HDR_FILL, HDR_FONT, BORDER
        c2.alignment = Alignment(text_rotation=90, wrap_text=True, horizontal="center", vertical="bottom")
        ws.column_dimensions[get_column_letter(j)].width = 7
    ws.row_dimensions[hr + 1].height = 230
    for i, (c, row) in enumerate(zip(causes, matrix), 1):
        rr = hr + 1 + i
        for j, v in enumerate([f"C{i:02d}", c["tag"], c["text"], c["group"]], 1):
            cell = ws.cell(rr, j, v)
            cell.border = BORDER
            cell.alignment = Alignment(wrap_text=True, vertical="center")
        for k, v in enumerate(row):
            cell = ws.cell(rr, len(heads) + 1 + k, v or None)
            cell.border = BORDER
            cell.alignment = Alignment(horizontal="center", vertical="center")
            if v:
                cell.fill = ACC_FILL
                cell.font = Font(bold=True)
    for j, w in enumerate([5, 11, 55, 7], 1):
        ws.column_dimensions[get_column_letter(j)].width = w
    ws.freeze_panes = ws.cell(hr + 2, len(heads) + 1)
    leg = hr + len(causes) + 3
    ws.cell(leg, 2, "Groups").font = Font(bold=True)
    for i, (g, d) in enumerate(GROUPS.items(), 1):
        ws.cell(leg + i, 2, g)
        ws.cell(leg + i, 3, d)
    ws.cell(leg + len(GROUPS) + 2, 2, "(X)").font = Font(bold=True)
    ws.cell(leg + len(GROUPS) + 2, 3, "Breaker already opened by electrical protection: PLC trip pulse is a confirmation only")
    wb.save(DOCS / "04_cause_and_effect.xlsx")

    flat = pd.DataFrame([[f"C{i:02d}", c["tag"], c["text"], c["group"]] + row
                         for i, (c, row) in enumerate(zip(causes, matrix), 1)],
                        columns=["#", "Cause tag", "Cause", "Group"] + [f"E{k + 1:02d}" for k in range(len(effects))])
    flat.to_csv(DOCS / "04_cause_and_effect.csv", index=False)
    eff = pd.DataFrame([[f"E{k + 1:02d}", e["tag"], e["text"]] for k, e in enumerate(effects)],
                       columns=["Effect", "Tag / function", "Action"])
    eff.to_csv(DOCS / "04_cause_and_effect_effects.csv", index=False)
    md = [f"# 04 – Cause & Effect matrix (Rev {REV})", "",
          "> Generated by `scripts/make_docs.py` from `tags.csv`. Formatted matrix: "
          "[04_cause_and_effect.xlsx](04_cause_and_effect.xlsx). Independent educational project, illustrative only.", "",
          "## Effects", "", md_table(eff), "", "## Matrix", "", md_table(flat), "",
          "## Groups", "", md_table(pd.DataFrame(list(GROUPS.items()), columns=["Group", "Meaning"])), "",
          "(X): breaker already opened by electrical protection; the PLC trip pulse is a confirmation only.", ""]
    (DOCS / "04_cause_and_effect.md").write_text("\n".join(md), encoding="utf-8")


if __name__ == "__main__":
    t = load_tags()
    io, summary = build_io(t)
    soft, alarms = build_soft(t), build_alarms(t)
    write_io(io, soft, alarms, summary)
    causes, effects, matrix = build_ce(t)
    write_ce(causes, effects, matrix)
    print(summary.to_string(index=False))
    print(f"I/O list: {len(io)} hardwired points, {len(soft)} software tags, {len(alarms)} alarms")
    print(f"C&E: {len(causes)} causes x {len(effects)} effects")
