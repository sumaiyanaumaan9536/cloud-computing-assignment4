#!/usr/bin/env bash
D=results/milestone4
mkdir -p $D/raw
ulimit -n 4096 2>/dev/null
echo "replicas,target_rate,sessions,duration_s,replies,achieved_rps,avg_resp_ms,client_errors,replies_2xx,replies_non2xx" > $D/fixed_summary.csv
python3 scripts/profile.py &
LOGPID=$!
for R in 1 2 3; do
  kubectl scale deployment emi-web --replicas=$R -n emi
  kubectl rollout status deployment/emi-web -n emi --timeout=120s
  sleep 30
  for RATE in 10 25 50 100 200; do
    L="r${R}_rate${RATE}"
    F=$D/raw/httperf_$L.txt
    echo "$(date +%T) RUN $L"
    echo $L > $D/current_run.txt
    httperf --server emi.local --port 80 --wsesslog=$((RATE*60)),0,$D/workload.txt --rate $RATE --timeout 5 --add-header='Content-Type: application/json\n' > $F 2>&1
    echo idle > $D/current_run.txt
    kubectl get pods -n emi > $D/raw/pods_after_$L.txt
    SESS=$(grep '^Total:' $F | awk '{print $3}')
    DUR=$(grep '^Total:' $F | awk '{print $9}')
    REPL=$(grep '^Total:' $F | awk '{print $7}')
    RPS=$(grep '^Request rate' $F | awk '{print $3}')
    RESP=$(grep '^Reply time' $F | awk '{print $5}')
    ERR=$(grep '^Errors: total' $F | awk '{print $3}')
    OK=$(grep '^Reply status' $F | sed 's/.*2xx=\([0-9]*\).*/\1/')
    echo "$R,$RATE,$SESS,$DUR,$REPL,$RPS,$RESP,$ERR,$OK,$((REPL-OK))" | tee -a $D/fixed_summary.csv
    sleep 20
  done
done
touch $D/stop
wait $LOGPID
echo "ALL 15 RUNS DONE"
