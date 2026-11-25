#!/usr/bin/env bash
# usage: scripts/selfheal_primary.sh  (deletes the current MongoDB PRIMARY while requests run)
OUT=results/milestone3
mkdir -p "$OUT"
REQ="$OUT/selfheal_primary_requests.log"
WATCH="$OUT/selfheal_primary_pods_watch.txt"
RS="$OUT/selfheal_primary_replset.txt"
: > "$REQ"; : > "$WATCH"; : > "$RS"
trap 'kill $LPID $WPID 2>/dev/null' EXIT

# member states + term, asked to whichever pod answers
status() {
  for p in mongo-0 mongo-1 mongo-2; do
    kubectl exec "$p" -n emi -- mongosh --quiet --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr)); print("term", rs.status().term)' 2>/dev/null && return
  done
}

PRIMARY=$(kubectl exec mongo-0 -n emi -- mongosh --quiet --eval 'print(db.hello().primary)' | cut -d. -f1 | tr -d '\r\n ')
echo "$(date +%T) BEFORE (PRIMARY=$PRIMARY)" >> "$RS"; status >> "$RS"

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

sleep 10
echo "$(date +%T) DELETING PRIMARY $PRIMARY" | tee -a "$WATCH" "$RS"
kubectl delete pod "$PRIMARY" -n emi --wait=false
for i in 1 2 3 4 5 6 7 8; do
  sleep 5
  echo "--- $(date +%T) (+$((i*5))s after delete)" >> "$RS"; status >> "$RS"
done

kill $LPID $WPID 2>/dev/null
echo "Deleted PRIMARY: $PRIMARY"
echo "Total requests: $(wc -l < "$REQ")"
echo "HTTP codes:"; awk '{print $4}' "$REQ" | sort | uniq -c
echo "Requests with no servedBy: $(grep -c ' NOPOD ' "$REQ")"
echo "First/last such request:"; grep ' NOPOD ' "$REQ" | sed -n '1p;$p'
echo "Final save check:"
curl -s -m 5 -X POST http://emi.local/api/emi -H "Content-Type: application/json" -d '{"P":500000,"rate":12,"n":24}'; echo
echo "Final replica set:"; status
