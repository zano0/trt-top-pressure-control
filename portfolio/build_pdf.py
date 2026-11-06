"""Build the portfolio PDF from portfolio/template.html and the simulation results.

Numbers are read from simulink/results/kpi_table.csv, so the PDF follows the simulations.
Outputs: portfolio/TRT_Control_Project_Andrea_Zanelli.pdf and portfolio/pages/page-N.png
(one PNG per page, used to check legibility and margins).

Usage:  .venv/bin/python portfolio/build_pdf.py
        (first time: .venv/bin/playwright install chromium)
"""
from __future__ import annotations

import json
from pathlib import Path
from string import Template

import pandas as pd
from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MAX_MB = 5.0


def numbers() -> dict:
    k = pd.read_csv(ROOT / "simulink" / "results" / "kpi_table.csv", index_col=0)
    mbar = lambda row: f"{1e3 * k.loc[row, 'max_dev_bar']:.0f}"  # noqa: E731
    return {
        "ff_peak": mbar("S3a trip, FF + tracking"),
        "fb_peak": mbar("S3b trip, feedback only"),
        "tight_peak": mbar("S3d trip, feedback only, tight PI + light filter"),
        "step_peak": mbar("S1a step +10 %"),
        "slip_peak": mbar("S2 slip +30 %/5 s"),
        "load_peak": f"{1e3 * k.loc['S4 loading, transfer FF', 'max_dev_bar']:.1f}",
    }


def tuning() -> dict:
    md = (ROOT / "simulink" / "results" / "kpi_table.md").read_text(encoding="utf-8")
    kp = ti = "?"
    for line in md.splitlines():
        if line.startswith("| PIC-100 Kp (SPLIT)"):
            kp = line.split("|")[2].strip().split()[0]
        if line.startswith("| PIC-100 Ti"):
            ti = line.split("|")[2].strip().split()[0]
    return {"kp": kp, "ti": f"{float(ti):.0f}" if ti != "?" else ti}


def short(url: str) -> str:
    """Display form of a URL: no scheme, no 'www.', no trailing slash."""
    return url.split("://", 1)[-1].removeprefix("www.").rstrip("/")


def main() -> None:
    cfg = json.loads((HERE / "config.json").read_text(encoding="utf-8"))
    values = {
        "name": cfg["name"], "role": cfg["role"], "degree": cfg["degree"], "email": cfg["email"],
        "github_url": cfg["github"], "github": short(cfg["github"]),
        "linkedin_url": cfg["linkedin"], "linkedin": short(cfg["linkedin"]),
        "p_el": "6.9", "sp": "1.8", "q_n": "280\u202f000",
        **numbers(), **tuning(),
    }
    html = Template((HERE / "template.html").read_text(encoding="utf-8")).substitute(values)
    page_file = HERE / "_build.html"
    page_file.write_text(html, encoding="utf-8")

    out = HERE / cfg["output"]
    shots = HERE / "pages"
    shots.mkdir(exist_ok=True)
    for old in shots.glob("page-*.png"):
        old.unlink()
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1123, "height": 794}, device_scale_factor=2)
        page.goto(page_file.as_uri())
        page.wait_for_load_state("networkidle")
        page.evaluate("document.fonts.ready")
        page.pdf(path=str(out), format="A4", landscape=True, print_background=True,
                 margin={"top": "0", "right": "0", "bottom": "0", "left": "0"})
        for i, sec in enumerate(page.query_selector_all("section.page"), 1):
            sec.screenshot(path=str(shots / f"page-{i}.png"))
        fonts = page.evaluate("[...document.fonts].filter(f => f.status === 'loaded').map(f => f.family)")
        browser.close()
    page_file.unlink()
    size = out.stat().st_size / 1e6
    print(f"Written {out} ({size:.2f} MB), page PNGs in {shots}, fonts loaded: {sorted(set(fonts))}")
    if size > MAX_MB:
        raise SystemExit(f"PDF larger than {MAX_MB} MB")


if __name__ == "__main__":
    main()
