# Loan EMI Calculator on Kubernetes (Minikube)

DS-584 Cloud Computing, Assignment 4.
A Node.js/Express Loan EMI Calculator that stores every calculation in a 3-member
MongoDB replica set, deployed on Minikube behind an NGINX Ingress, with load
testing and Horizontal Pod Autoscaling.

## Repository structure

| Path | Content |
|---|---|
| `app/` | Node.js/Express server (`server.js`) and front end in `public/` (HTML, jQuery, Bootstrap) |
| `Dockerfile`, `.dockerignore` | Image build (`emi-web`, non-root user) |
| `k8s/` | Kubernetes manifests: namespace, MongoDB, init Job, web app, Ingress, HPA |
| `scripts/` | Load-test, profiling, autoscaling and graph scripts |
| `results/` | Raw outputs for Milestones 2-4 and the graphs |

## Application endpoints

- `POST /api/emi`: body with principal, rate and months; returns EMI, total payment, total interest, pod name and IP
- `GET /api/history`: last 10 calculations, newest first
- `GET /health`: HTTP 200 only when MongoDB is reachable (readiness and liveness probe)
- The MongoDB connection string is read from the `MONGO_URL` environment variable (set from a ConfigMap)

## Prerequisites

Ubuntu with Docker, `kubectl` and Minikube. Python 3 with pandas and matplotlib is
needed only for the graphs, and `httperf` only for load tests.

## Bring up the whole system on a fresh Minikube cluster

```bash
# 1. Start the cluster and enable the add-ons
minikube start
minikube addons enable ingress
minikube addons enable metrics-server

# 2. Build the image and load it into Minikube
docker build -t emi-web:1.0 .
minikube image load emi-web:1.0

# 3. Apply all manifests (00-namespace.yaml creates the emi namespace first)
kubectl apply -f k8s/

# 4. Watch the pods until they are Running and Ready
kubectl get pods -n emi -w
```

`kubectl apply -f k8s/` creates the namespace, the headless `mongo` Service, the `mongo`
StatefulSet (3 replicas, 1 Gi PVC each), the `mongo-init` Job, the ConfigMap, the
`emi-web` Deployment and Service, the Ingress and the HPA.

The `mongo-init` Job may fail its first attempts if the MongoDB pods are not up yet.
If it ends in an error, wait until `mongo-0`, `mongo-1` and `mongo-2` are Running, then run:

```bash
kubectl delete job mongo-init -n emi
kubectl apply -f k8s/
```

### Verify the replica set

```bash
kubectl logs job/mongo-init -n emi
kubectl exec -n emi mongo-0 -- mongosh --quiet --eval "rs.status().members.forEach(m => print(m.name, m.stateStr))"
```

Expected: one PRIMARY and two SECONDARY members.

### Test through port-forward

```bash
kubectl port-forward svc/emi-web 8080:80 -n emi
# open http://localhost:8080
```

### Access through the Ingress

```bash
echo "$(minikube ip) emi.local" | sudo tee -a /etc/hosts
# open http://emi.local (with the Docker driver: run `minikube tunnel` and use 127.0.0.1)
```

## Load testing, profiling and autoscaling (Milestone 4)

- `scripts/profile.py` saves per-pod CPU/memory (`kubectl top pods`, every 15 s) and host CPU
  (every second) to timestamped CSV files.
- `scripts/autoscale_test.sh` runs the 10-minute HPA test (2 min at 10 req/s, 5 min at
  100 req/s, 3 min at 10 req/s) and records the replica count every 15 s.
- `scripts/make_graphs.py` creates the three graphs in `results/graphs/`:

```bash
python3 scripts/make_graphs.py
```

Raw outputs are in `results/milestone2/`, `results/milestone3/` and `results/milestone4/`.

## Clean up

```bash
kubectl delete namespace emi
minikube stop
```
