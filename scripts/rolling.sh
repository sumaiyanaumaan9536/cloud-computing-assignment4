#!/usr/bin/env bash
MODE=${1:?usage: rolling.sh update|rollback}
OUT=results/milestone3
mkdir -p "$OUT"
REQ="$OUT/rolling_${MODE}_requests.log"
WATCH="$OUT/rolling_${MODE}_pods_watch.txt"
STATUS="$OUT/rolling_${MODE}_rollout.txt"
: > "$REQ"; : > "$WATCH"; : > "$STATUS"
trap 'kill $LPID $WPID 2>/dev/null' EXIT
kubectl get pods -n emi -w | while read -r line; do echo "$(date +%T) $line"; done > "$WATCH" &
WPID=$!
( i=0; while true; do
    i=$((i+1))
    P=$((RANDOM % 900000 + 100000)); RATE=$((RANDOM % 15 + 5)); M=$((RANDOM % 48 + 12))
    R=$(curl -s -m 5 -w '\n%{http_code}' -X POST http://emi.local/api/emi -H "Content-Type: application/json" -d "{\"P\":$P,\"rate\":$RATE,\"n\":$M}")
    CODE=$(echo "$R" | tail -1)
    POD=$(echo "$R" | sed -n 's/.*"servedBy":"\([^"]*\)".*/\1/p')
    echo "$(date +%T) $i ${POD:-NOPOD} $CODE" >> "$REQ"
    sleep 0.2
  done ) &
LPID=$!
sleep 5
echo "$(date +%T) START $MODE" | tee -a "$STATUS"
if [ "$MODE" = update ]; then
  kubectl set image deployment/emi-web '*=emi-web:1.1' -n emi | tee -a "$STATUS"
else
  kubectl rollout undo deployment/emi-web -n emi | tee -a "$STATUS"
fi
kubectl rollout status deployment/emi-web -n emi --timeout=300s | tee -a "$STATUS"
echo "$(date +%T) ROLLOUT DONE" | tee -a "$STATUS"
sleep 10
kill $LPID $WPID 2>/dev/null
echo "--- rollout history" | tee -a "$STATUS"
kubectl rollout history deployment/emi-web -n emi | tee -a "$STATUS"
echo "Image now: $(kubectl get deploy emi-web -n emi -o jsonpath='{.spec.template.spec.containers[0].image}')" | tee -a "$STATUS"
echo "Page title served: $(curl -s -m 5 http://emi.local/ | grep -i -o '<title>[^<]*</title>')" | tee -a "$STATUS"
echo "Total requests: $(wc -l < "$REQ")" | tee -a "$STATUS"
echo "HTTP codes:" | tee -a "$STATUS"
awk '{print $4}' "$REQ" | sort | uniq -c | tee -a "$STATUS"
echo "Requests with no servedBy: $(grep -c ' NOPOD ' "$REQ")" | tee -a "$STATUS"
echo "Served per pod:" | tee -a "$STATUS"
awk '{print $3}' "$REQ" | sort | uniq -c | sort -rn | tee -a "$STATUS"
