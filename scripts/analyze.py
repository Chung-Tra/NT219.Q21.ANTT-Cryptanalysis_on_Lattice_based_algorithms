#!/usr/bin/env python3
# =============================================================================
# analyze.py - Aggregate benchmark CSVs into tables + charts (brief section 9
# "Presentation": latency vs parameter set, throughput, bytes vs algorithm;
# week-11 "statistical analysis, prepare figures & tables").
#
# Inputs (any subset may exist; produced by the measurement scripts):
#   data/summary_micro_<arch>.csv   long format: algo,metric,value
#   data/memory_<arch>.csv          algo,peak_rss_kb
#   data/codesize_<arch>.csv        file,text_bytes,data_bytes,bss_bytes,total_bytes
#   data/tls_handshake_<arch>.csv   arch,cert,group,hs_median_ms,...,cert_bytes
#
# Output: analysis_out/tables.md (+ *.png charts when matplotlib is available)
# Usage : python3 scripts/analyze.py        (from repo root or anywhere)
# =============================================================================
import csv
import sys
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
OUT = ROOT / "analysis_out"
OUT.mkdir(exist_ok=True)

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    HAVE_MPL = True
except ImportError:
    HAVE_MPL = False
    print("NOTE: matplotlib not found -> tables only "
          "(pip install matplotlib --break-system-packages)")


def read_csv(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def fnum(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def md_table(headers, rows):
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join(["---"] * len(headers)) + "|"]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return "\n".join(out) + "\n"


def bar_chart(labels, series, title, ylabel, fname, log=False):
    """series: list of (name, values) drawn side by side."""
    if not HAVE_MPL or not labels:
        return
    import numpy as np
    x = np.arange(len(labels))
    width = 0.8 / max(len(series), 1)
    fig, ax = plt.subplots(figsize=(max(6, len(labels) * 0.9), 4))
    for i, (name, vals) in enumerate(series):
        ax.bar(x + i * width, vals, width, label=name)
    ax.set_xticks(x + width * (len(series) - 1) / 2)
    ax.set_xticklabels(labels, rotation=30, ha="right", fontsize=8)
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    if log:
        ax.set_yscale("log")
    if len(series) > 1:
        ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(OUT / fname, dpi=140)
    plt.close(fig)
    print(f"  chart: analysis_out/{fname}")


report = ["# Benchmark analysis\n"]
arches = sorted({p.stem.removeprefix("summary_micro_") for p in DATA.glob("summary_micro_*.csv")})

# ---- 1) Microbenchmark latency (WP2): long format algo,metric,value --------
micro = {}  # arch -> algo -> metric -> value
for arch in arches:
    rows = read_csv(DATA / f"summary_micro_{arch}.csv")
    table = defaultdict(dict)
    for r in rows:
        v = fnum(r.get("value"))
        if v is not None:
            table[r["algo"]][r["metric"]] = v
    micro[arch] = table

for arch, table in micro.items():
    medians = sorted({m for a in table.values() for m in a if "median" in m})
    if not medians:
        continue
    report.append(f"\n## Microbenchmark medians ({arch})\n")
    algos = sorted(table)
    rows = [[a] + [table[a].get(m, "") for m in medians] for a in algos]
    report.append(md_table(["algo"] + medians, rows))
    for m in medians:
        labels = [a for a in algos if m in table[a]]
        bar_chart(labels, [(arch, [table[a][m] for a in labels])],
                  f"{m} ({arch})", m, f"micro_{m}_{arch}.png", log=True)

# Cross-arch ratio (valid bridge: same algo, ratio across machines)
if len(micro) >= 2:
    a1, a2 = sorted(micro)[:2]
    common = sorted(set(micro[a1]) & set(micro[a2]))
    mets = sorted({m for a in common for m in micro[a1][a] if "median" in m})
    rows = []
    for a in common:
        for m in mets:
            v1, v2 = micro[a1][a].get(m), micro[a2][a].get(m)
            if v1 and v2:
                rows.append([a, m, v1, v2, f"{v2 / v1:.2f}x"])
    if rows:
        report.append(f"\n## Cross-platform ratio ({a2} / {a1})\n")
        report.append(md_table(["algo", "metric", a1, a2, "ratio"], rows))

# ---- 2) Peak RSS (WP5) ------------------------------------------------------
for p in sorted(DATA.glob("memory_*.csv")):
    arch = p.stem.removeprefix("memory_")
    rows = read_csv(p)
    rows = [r for r in rows if fnum(r.get("peak_rss_kb")) is not None]
    if not rows:
        continue
    report.append(f"\n## Peak RSS ({arch})\n")
    report.append(md_table(["algo", "peak_rss_kb"],
                           [[r["algo"], r["peak_rss_kb"]] for r in rows]))
    bar_chart([r["algo"] for r in rows],
              [(arch, [fnum(r["peak_rss_kb"]) for r in rows])],
              f"Peak RSS ({arch})", "KB", f"memory_{arch}.png")

# ---- 3) Code size (WP5) -----------------------------------------------------
for p in sorted(DATA.glob("codesize_*.csv")):
    arch = p.stem.removeprefix("codesize_")
    rows = read_csv(p)
    rows = [r for r in rows if fnum(r.get("total_bytes")) is not None]
    if not rows:
        continue
    rows.sort(key=lambda r: -fnum(r["total_bytes"]))
    report.append(f"\n## Code size ({arch})\n")
    report.append(md_table(["file", "text", "data", "bss", "total"],
                           [[r["file"], r["text_bytes"], r["data_bytes"],
                             r["bss_bytes"], r["total_bytes"]] for r in rows]))
    bar_chart([r["file"] for r in rows],
              [(arch, [fnum(r["total_bytes"]) / 1024 for r in rows])],
              f"Code size ({arch})", "KiB", f"codesize_{arch}.png", log=True)

# ---- 4) TLS handshake (WP4) -------------------------------------------------
for p in sorted(DATA.glob("tls_handshake_*.csv")):
    arch = p.stem.removeprefix("tls_handshake_")
    rows = read_csv(p)
    if not rows:
        continue
    report.append(f"\n## TLS 1.3 handshake ({arch})\n")
    report.append(md_table(
        ["cert", "group", "median_ms", "p95_ms", "hs/s", "conc", "cert_bytes"],
        [[r["cert"], r["group"], r["hs_median_ms"], r["hs_p95_ms"],
          r["throughput_hs_s"], r["concurrency"], r["cert_bytes"]] for r in rows]))
    ok = [r for r in rows if fnum(r.get("hs_median_ms")) is not None]
    groups = sorted({r["group"] for r in ok})
    certs = sorted({r["cert"] for r in ok})
    if groups and certs:
        series = []
        for c in certs:
            by = {r["group"]: fnum(r["hs_median_ms"]) for r in ok if r["cert"] == c}
            series.append((c, [by.get(g, 0) for g in groups]))
        bar_chart(groups, series, f"TLS handshake median ({arch})",
                  "ms", f"tls_latency_{arch}.png")
        series = []
        for c in certs:
            by = {r["group"]: fnum(r["throughput_hs_s"]) for r in ok if r["cert"] == c}
            series.append((c, [by.get(g, 0) for g in groups]))
        bar_chart(groups, series, f"TLS handshakes/s, conc={ok[0]['concurrency']} ({arch})",
                  "handshakes/s", f"tls_throughput_{arch}.png")

# ---- 5) liboqs ref vs opt (WP3: NEON / AVX2 effect) -------------------------
for p in sorted(DATA.glob("liboqs_speed_*.csv")):
    arch = p.stem.removeprefix("liboqs_speed_")
    rows = read_csv(p)
    by = defaultdict(dict)  # (algo, op) -> variant -> mean_us
    for r in rows:
        v = fnum(r.get("mean_us"))
        if v is not None:
            by[(r["algo"], r["op"])][r["variant"]] = v
    pairs = [(a, o, d["ref"], d["opt"], d["ref"] / d["opt"])
             for (a, o), d in sorted(by.items())
             if d.get("ref") and d.get("opt")]
    if not pairs:
        continue
    report.append(f"\n## liboqs ref vs opt ({arch}) - speedup = ref/opt\n")
    report.append(md_table(
        ["algo", "op", "ref_us", "opt_us", "speedup"],
        [[a, o, f"{r1:.3f}", f"{r2:.3f}", f"x{sp:.2f}"]
         for a, o, r1, r2, sp in pairs]))
    labels = [f"{a}.{o}" for a, o, *_ in pairs]
    bar_chart(labels, [("opt vs ref", [sp for *_, sp in pairs])],
              f"Optimization speedup ref->opt ({arch})", "x times",
              f"liboqs_speedup_{arch}.png")

(OUT / "tables.md").write_text("\n".join(report))
print(f"DONE. Tables: analysis_out/tables.md"
      + ("" if HAVE_MPL else "  (charts skipped: no matplotlib)"))
if not any(DATA.glob("*.csv")):
    print("WARNING: data/ has no CSVs yet - run 'make bench' / 'make memory' / "
          "'make codesize' / scripts/bench_tls.sh first")
    sys.exit(1)
