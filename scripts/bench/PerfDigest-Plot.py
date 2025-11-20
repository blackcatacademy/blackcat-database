import json, argparse, os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
ap = argparse.ArgumentParser()
ap.add_argument("--in", dest="inp", required=True)
ap.add_argument("--outdir", required=True)
args = ap.parse_args()
os.makedirs(args.outdir, exist_ok=True)
with open(args.inp, "r") as fh:
    data = json.load(fh)
top = sorted(data, key=lambda r: r.get("mean_time", 0), reverse=True)[:10]
labels = [str(r.get("queryid"))[-8:] for r in top]
means = [r.get("mean_time", 0) for r in top]
plt.figure()
plt.bar(range(len(means)), means)
plt.xticks(range(len(means)), labels, rotation=45, ha='right')
plt.title("Top 10 query mean_time (ms)")
plt.ylabel("ms")
plt.tight_layout()
png = os.path.join(args.outdir, "pg_perfdigest_top10_mean.png")
plt.savefig(png)
print("Wrote", png)
