#!/usr/bin/env bash
D=results/milestone4/autoscale
mkdir -p $D
kubectl delete hpa emi-web -n emi --ignore-not-found
kubectl scale deployment emi-web --replicas=1 -n emi
kubectl rollout status deployment/emi-web -n emi --timeout=120s
sleep 30
kubectl apply -f k8s/hpa.yaml
echo "timestamp,phase,current_replicas,desired_replicas,cpu_percent" > $D/hpa_replicas.csv
: > $D/hpa_raw.txt
: > $D/phases.log
rm -f results/milestone4/stop
python3 scripts/profile.py &
LOGPID=$!
( while [ ! -f results/milestone4/stop ]; do
    T=$(date +"%Y-%m-%d %H:%M:%S")
    PH=$(cat results/milestone4/current_run.txt 2>/dev/null)
    V=$(kubectl get hpa emi-web -n emi -o jsonpath='{.status.currentReplicas},{.status.desiredReplicas},{.status.currentMetrics[0].resource.current.averageUtilization}')
    echo "$T,$PH,$V" >> $D/hpa_replicas.csv
    echo "$T $PH" >> $D/hpa_raw.txt
    kubectl get hpa emi-web -n emi --no-headers >> $D/hpa_raw.txt
    sleep 15
  done ) &
HPAPID=$!
run_phase() {
  echo $1 > results/milestone4/current_run.txt
  echo "$(date +%T) START $1 rate=$2 sessions=$3" | tee -a $D/phases.log
  httperf --server emi.local --port 80 --wsesslog=$3,0,results/milestone4/workload.txt --rate $2 --timeout 5 --add-header='Content-Type: application/json\n' > $D/httperf_$1.txt 2>&1
  echo "$(date +%T) END $1" | tee -a $D/phases.log
}
run_phase phase1_10rps 10 1200
run_phase phase2_100rps 100 30000
run_phase phase3_10rps 10 1800
echo idle > results/milestone4/current_run.txt
touch results/milestone4/stop
wait $LOGPID $HPAPID
mv results/milestone4/host_cpu.csv results/milestone4/pod_top.csv $D/
kubectl get hpa emi-web -n emi | tee $D/hpa_final.txt
echo "AUTOSCALE TEST DONE"
