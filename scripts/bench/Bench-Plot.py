import argparse, glob, csv, statistics, os, json

import matplotlib.pyplot as plt

def load_rows(glob_pattern):
    files = glob.glob(glob_pattern)
    rows = []
    for f in files:
        with open(f, newline='') as fh:
            rd = csv.DictReader(fh)
            rows.extend(rd)
    return rows

def to_int(s, default=0):
    try:
        return int(s)
    except Exception:
        return default

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glob", required=True, help="CSV glob, e.g. bench/results/*.csv")
    ap.add_argument("--outdir", default="bench/plots")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    rows = load_rows(args.glob)
    ms = [to_int(r.get("ms", 0)) for r in rows if r.get("ms") is not None]
    ok = [r for r in rows if str(r.get("ok", "")) == "1"]
    err = len(rows) - len(ok)

    if not rows or not ms:
        print("No rows found")
        # still write empty artifacts for pipeline robustness
        metrics = {"total": len(rows), "ok": len(ok), "err": err, "avg": 0, "p50": 0, "p95": 0, "p99": 0}
        with open(os.path.join(args.outdir, "metrics.json"), "w") as fh:
            json.dump(metrics, fh)
        with open(os.path.join(args.outdir, "SUMMARY.md"), "w") as fh:
            fh.write("# Bench Summary\n\nNo data.\n")
        print("BENCH_P95=0")
        print("BENCH_AVG=0")
        return

    ms_sorted = sorted(ms)
    def pct(p):
        k = max(0, min(len(ms_sorted)-1, int(round((p/100.0)*(len(ms_sorted)-1)))))
        return ms_sorted[k]

    avg = int(round(statistics.mean(ms)))
    p50 = pct(50); p95 = pct(95); p99 = pct(99)

    # Use non-interactive backend
    import matplotlib
    matplotlib.use("Agg")

    # Histogram
    plt.figure()
    plt.hist(ms, bins=50)
    plt.title("Latency Histogram (ms)")
    plt.xlabel("ms")
    plt.ylabel("count")
    plt.tight_layout()
    hist_path = os.path.join(args.outdir, "latency_histogram_ci.png")
    plt.savefig(hist_path)
    plt.close()

    # Timeseries (per iteration index)
    iters = [to_int(r.get("iter", 0)) for r in rows]
    plt.figure()
    plt.plot(iters, ms)
    plt.title("Latency by Iteration")
    plt.xlabel("iteration")
    plt.ylabel("ms")
    plt.tight_layout()
    ts_path = os.path.join(args.outdir, "latency_timeseries_ci.png")
    plt.savefig(ts_path)
    plt.close()

    metrics = {"total": len(rows), "ok": len(ok), "err": err, "avg": avg, "p50": p50, "p95": p95, "p99": p99}
    with open(os.path.join(args.outdir, "metrics.json"), "w") as fh:
        json.dump(metrics, fh, indent=2)

    summary = f"""# Bench Summary

- Total ops: {len(rows)}, OK: {len(ok)}, ERR: {err}
- Latency ms: avg={avg}, p50={p50}, p95={p95}, p99={p99}

Artifacts:
- {hist_path}
- {ts_path}
"""
    with open(os.path.join(args.outdir, "SUMMARY.md"), "w") as fh:
        fh.write(summary)

    # Markers for easy grep
    print(f"BENCH_P95={p95}")
    print(f"BENCH_AVG={avg}")

if __name__ == "__main__":
    main()
