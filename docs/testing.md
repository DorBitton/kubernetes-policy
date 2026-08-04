# Reproducing the edge-case tests

Not part of install — these are the exact commands used to demonstrate the
edge cases listed in the top-level README. Run after `install/setup.sh`.

## Baseline + conflicting-constraint fixtures

```
kubectl apply -f test-apps/app-no-constraints/deployment.yaml
kubectl get pods -l app=app-no-constraints -o wide

kubectl apply -f test-apps/app-soft-affinity/deployment.yaml
kubectl get pods -l app=app-soft-affinity -o wide

kubectl apply -f test-apps/app-hard-affinity/deployment.yaml
kubectl get pods -l app=app-hard-affinity -o wide
```

## Case 1 — capacity added after pods already scheduled

```
kubectl cordon zone-policy-worker3
kubectl cordon zone-policy-worker4
kubectl rollout restart deployment/app-no-constraints
kubectl rollout status deployment/app-no-constraints --timeout=60s
kubectl get pods -l app=app-no-constraints -o wide
# result: all replicas land on zone-a (only uncordoned zone)

kubectl uncordon zone-policy-worker3
kubectl uncordon zone-policy-worker4
kubectl get pods -l app=app-no-constraints -o wide
# result: unchanged - no automatic rebalance once capacity returns
```

## Case 2 — capacity lost while pods are running (simulated AZ outage)

```
kubectl rollout restart deployment/app-no-constraints
kubectl rollout status deployment/app-no-constraints --timeout=60s
kubectl get pods -l app=app-no-constraints -o wide

kubectl drain zone-policy-worker3 --ignore-daemonsets --delete-emptydir-data --force
kubectl get pods -l app=app-no-constraints -o wide
# result: evicted pods reschedule onto remaining zones, e.g. 3/0/3

kubectl uncordon zone-policy-worker3
kubectl get pods -l app=app-no-constraints -o wide
# result: unchanged - no automatic rebalance back once zone-b returns
```

## Cleanup

```
kubectl delete pods -l app=app-no-constraints --field-selector=status.phase=Succeeded
```
