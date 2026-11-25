#!/usr/bin/env bash
# usage: scripts/selfheal_web.sh   (deletes one web pod while requests run)
OUT=results/milestone3
mkdir -p "$OUT"
REQ="$OUT/selfheal_web_requests.log"
WATCH="$OUT/selfheal_web_pods_watch.txt"
: > "$REQ"; : > "$WATCH"

# 1. watch pods with timestamps (evidence for kubectl get pods -w)
kubectl get pods -n emi -w | while read -r line; do echo "$(date +%T) $line"; done > "$WATCH" &
WPID=$!

# 2. continuous POST loop (about 4 requests/second)
( i=0; while true; do
    i=$((i+1))
    P=$((RANDOM % 900000 + 100000)); RATE=$((RANDOM % 15 + 5)); M=$((RANDOM % 48 + 12))
    R=$(curl -s -m 5 -X POST http://emi.local/api/emi -H "Content-Type: application/json" -d "{\"P\":$P,\"rate\":$RATE,\"n\":$M}")
    POD=$(echo "$R" | sed -n 's/.*"servedBy":"\([^"]*\)".*/\1/p')
    echo "$(date +%T) $i ${POD:-FAILED}" >> "$REQ"
    sleep 0.2
  done ) &
LPID=$!

sleep 10
VICTIM=$(kubectl get pods -n emi -l app=emi-web -o jsonpath='{.items[0].metadata.name}')
echo "$(date +%T) DELETING $VICTIM" | tee -a "$WATCH"
kubectl delete pod "$VICTIM" -n emi --wait=false
sleep 45

kill $LPID $WPID 2>/dev/null
echo "Deleted pod: $VICTIM"
echo "Total requests: $(wc -l < "$REQ")   Failed: $(grep -c FAILED "$REQ")"
echo "Served per pod:"; awk '{print $3}' "$REQ" | sort | uniq -c | sort -rn
