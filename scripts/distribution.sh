#!/usr/bin/env bash
# usage: scripts/distribution.sh <label> [requests]
LABEL=${1:?usage: distribution.sh <label> [requests]}
N=${2:-30}
OUT=results/milestone3
mkdir -p "$OUT"
LOG="$OUT/distribution_${LABEL}.log"
term() { kubectl exec mongo-2 -n emi -- mongosh --quiet --eval 'print(rs.status().term)' | tr -dc '0-9'; }
T1=$(term)
: > "$LOG"
for i in $(seq 1 "$N"); do
  P=$((RANDOM % 900000 + 100000)); RATE=$((RANDOM % 15 + 5)); M=$((RANDOM % 48 + 12))
  R=$(curl -s -m 5 -X POST http://emi.local/api/emi -H "Content-Type: application/json" -d "{\"P\":$P,\"rate\":$RATE,\"n\":$M}")
  POD=$(echo "$R" | sed -n 's/.*"servedBy":"\([^"]*\)".*/\1/p')
  echo "$i ${POD:-FAILED}" >> "$LOG"
done
T2=$(term)
echo "Requests served per pod ($LABEL, $N requests):"
awk '{print $2}' "$LOG" | sort | uniq -c | sort -rn
echo "replica-set term before: $T1, after: $T2"
