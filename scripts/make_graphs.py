import re, glob, os
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

R = "results/milestone4"
G = "results/graphs"
os.makedirs(G, exist_ok=True)

def grab(txt, pat, cast=float):
    m = re.search(pat, txt)
    return cast(m.group(1)) if m else None

def parse(path):
    t = open(path).read()
    return dict(
        requests=grab(t, r"requests (\d+) replies", int),
        replies=grab(t, r"replies (\d+) test-duration", int),
        duration=grab(t, r"test-duration ([\d.]+) s"),
        resp_ms=grab(t, r"Reply time \[ms\]: response ([\d.]+)"),
        s2xx=grab(t, r"2xx=(\d+)", int),
        s5xx=grab(t, r"5xx=(\d+)", int),
        errors=grab(t, r"Errors: total (\d+)", int),
    )

# ---------- Graph 1 + results table ----------
rows = []
for f in sorted(glob.glob(f"{R}/raw/httperf_r*_rate*.txt")):
    m = re.search(r"httperf_r(\d)_rate(\d+)\.txt", f)
    d = parse(f)
    d["replicas"], d["rate"] = int(m.group(1)), int(m.group(2))
    d["achieved_reply_rate"] = round(d["replies"] / d["duration"], 1)
    rows.append(d)
df = pd.DataFrame(rows).sort_values(["replicas", "rate"])
df = df[["replicas","rate","requests","replies","achieved_reply_rate","resp_ms","s2xx","s5xx","errors","duration"]]
df.to_csv(f"{G}/fixed_runs_table.csv", index=False)
print(df.to_string(index=False))

plt.figure(figsize=(8, 5))
for r, g in df.groupby("replicas"):
    plt.plot(g["rate"], g["resp_ms"], marker="o", label=f"{r} replica(s)")
plt.xlabel("Target request rate (req/s)")
plt.ylabel("Average response time (ms)")
plt.title("Graph 1: Average response time vs request rate")
plt.grid(True, alpha=0.3); plt.legend(); plt.tight_layout()
plt.savefig(f"{G}/graph1_response_time.png", dpi=150); plt.close()

# ---------- Graph 2 ----------
p = pd.read_csv(f"{R}/fixed_profile/pod_top.csv", parse_dates=["timestamp"])
print("Labels in pod_top.csv:", sorted(p["label"].unique()))
sel = p[(p["label"].str.contains("r3")) & (p["label"].str.contains("rate100")) & (p["pod"].str.startswith("emi-web"))]
if sel.empty:
    print("!! No rows matched r3 + rate100. Check the labels printed above.")
else:
    plt.figure(figsize=(9, 5))
    t0 = sel["timestamp"].min()
    for pod, g in sel.groupby("pod"):
        x = (g["timestamp"] - t0).dt.total_seconds()
        plt.plot(x, g["cpu_millicores"] / 100 * 100, marker="o", label=pod)  # % of 100m request
    plt.axhline(250 / 100 * 100, color="red", ls="--", lw=1, label="CPU limit (250m = 250%)")
    plt.xlabel("Time since start of run (s)")
    plt.ylabel("CPU utilization (% of 100m request)")
    plt.title("Graph 2: Per-pod CPU, 100 req/s, 3 replicas")
    plt.grid(True, alpha=0.3); plt.legend(); plt.tight_layout()
    plt.savefig(f"{G}/graph2_pod_cpu.png", dpi=150); plt.close()

# ---------- Graph 3 ----------
h = pd.read_csv(f"{R}/autoscale/hpa_replicas.csv", parse_dates=["timestamp"])
t0 = h["timestamp"].min()
h["x"] = (h["timestamp"] - t0).dt.total_seconds() / 60
target = {"phase1_10rps": 10, "phase2_100rps": 100, "phase3_10rps": 10}
h["target_rate"] = h["phase"].map(target)
ach = {}
for ph in target:
    d = parse(f"{R}/autoscale/httperf_{ph}.txt")
    ach[ph] = d["replies"] / d["duration"]
h["achieved_rate"] = h["phase"].map(ach)

fig, ax = plt.subplots(3, 1, figsize=(10, 9), sharex=True)
ax[0].step(h["x"], h["target_rate"], where="post", label="Target rate")
ax[0].step(h["x"], h["achieved_rate"], where="post", ls="--", label="Achieved reply rate (avg of phase)")
ax[0].set_ylabel("Requests/s"); ax[0].legend(); ax[0].grid(True, alpha=0.3)
ax[0].set_title("Graph 3: Autoscaling test (10 min)")
ax[1].plot(h["x"], h["cpu_percent"], marker="o")
ax[1].axhline(50, color="red", ls="--", label="HPA target 50%")
ax[1].set_ylabel("Avg CPU (% of request)"); ax[1].legend(); ax[1].grid(True, alpha=0.3)
ax[2].step(h["x"], h["current_replicas"], where="post", label="Current replicas")
ax[2].step(h["x"], h["desired_replicas"], where="post", ls="--", label="Desired replicas")
ax[2].set_ylabel("Web replicas"); ax[2].set_xlabel("Time (minutes)")
ax[2].set_yticks(range(0, 6)); ax[2].legend(); ax[2].grid(True, alpha=0.3)
for a in ax:
    for ph in ["phase2_100rps", "phase3_10rps"]:
        a.axvline(h[h["phase"] == ph]["x"].min(), color="gray", ls=":")
plt.tight_layout()
plt.savefig(f"{G}/graph3_autoscaling.png", dpi=150); plt.close()
print("DONE")
