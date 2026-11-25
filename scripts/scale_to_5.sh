#!/usr/bin/env bash
OUT=results/milestone3
mkdir -p "$OUT"
term() { kubectl exec mongo-2 -n emi -- mongosh --quiet --eval 'print(rs.status().term)' | tr -dc '0-9'; }
echo "term before: $(term)"
kubectl get pods -n emi -l app=emi-web -w --no-headers | while read -r l; do echo "$(date +%T) $l"; done > "$OUT/scale5_pods_watch.txt" &
( while true; do
    R=$(curl -s -m 3 -X POST http://emi.local/api/emi -H "Content-Type: application/json" -d '{"P":500000,"rate":12,"n":24}')
    POD=$(echo "$R" | sed -n 's/.*"servedBy":"\([^"]*\)".*/\1/p')
    echo "$(date +%T) ${POD:-FAILED}"
    sleep 0.5
  done ) > "$OUT/scale5_ramp_requests.txt" &
LOOP=$!
sleep 3
echo "$(date +%T) scaling to 5"
kubectl scale deployment emi-web --replicas=5 -n emi
kubectl rollout status deployment/emi-web -n emi --timeout=180s
sleep 10
kill "$LOOP" 2>/dev/null
pkill -f "kubectl get pods -n emi -l app=emi-web -w"
echo "$(date +%T) done"
echo "term after: $(term)"
kubectl get deploy emi-web -n emi
