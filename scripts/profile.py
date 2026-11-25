import csv, subprocess, time, os, psutil
D = "results/milestone4"
STOP = D + "/stop"
if os.path.exists(STOP):
    os.remove(STOP)
def label():
    try:
        return open(D + "/current_run.txt").read().strip()
    except Exception:
        return "idle"
h = open(D + "/host_cpu.csv", "w", newline="")
hw = csv.writer(h)
hw.writerow(["timestamp", "label", "cpu_percent"])
p = open(D + "/pod_top.csv", "w", newline="")
pw = csv.writer(p)
pw.writerow(["timestamp", "label", "pod", "cpu_millicores", "memory_mi"])
i = 0
while not os.path.exists(STOP):
    c = psutil.cpu_percent(interval=1)
    t = time.strftime("%Y-%m-%d %H:%M:%S")
    hw.writerow([t, label(), c])
    h.flush()
    if i % 15 == 0:
        out = subprocess.run(["kubectl", "top", "pods", "-n", "emi", "--no-headers"], capture_output=True, text=True).stdout
        for line in out.splitlines():
            f = line.split()
            if len(f) >= 3:
                pw.writerow([t, label(), f[0], f[1].rstrip("m"), f[2].rstrip("Mi")])
        p.flush()
    i += 1
