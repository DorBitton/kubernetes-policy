# Reproducing the edge-case tests

Commands used to demonstrate the edge cases in the top-level README. Run after
`install/setup.sh` — policy not applied yet, see below.

## Deploy the fixtures

```
kubectl apply -f test-apps/app-no-constraints/deployment.yaml
kubectl apply -f test-apps/app-soft-affinity/deployment.yaml
kubectl apply -f test-apps/app-hard-affinity/deployment.yaml
```

These three don't behave the same way, and it's not obvious until you look:

```
kubectl get pods -l app=app-no-constraints -o wide
# result: already reasonably spread (e.g. 2/2/2 across zones), with no policy
# applied yet and no constraints in the manifest. kube-scheduler spreads pods
# owned by a Deployment/ReplicaSet across zones and hosts by default, as a soft
# scoring preference, even without an explicit topologySpreadConstraints. With
# free capacity in every zone that's usually enough to look fine on its own -
# this fixture's "bad" case only shows up once capacity is missing, in Case 1
# and Case 2 below.

kubectl get pods -l app=app-soft-affinity -o wide
# result: all 6 pods in zone-a, right now, no cordoning needed. A weight-100
# preferred nodeAffinity is a strong enough score to dominate the scheduler's
# default spread preference.

kubectl get pods -l app=app-hard-affinity -o wide
# result: all 6 pods in zone-a, right now, no cordoning needed. A required
# nodeAffinity filters out every other zone before scoring even runs, so there
# was never a choice to spread in the first place.
```

## Applying policy after the fact

Deployments above were created against a bare cluster (no policy applied
yet), so none of them have any injected constraints at this point. Now apply
policy and confirm nothing already running gets touched retroactively, but
the next update does:

```
kubectl get deployment app-no-constraints -o jsonpath='{.spec.template.spec.topologySpreadConstraints}'
# result: empty - policy doesn't exist yet

./install/apply-policy.sh

kubectl get deployment app-no-constraints -o jsonpath='{.spec.template.spec.topologySpreadConstraints}'
# result: still empty - applying a policy doesn't retroactively touch existing objects

kubectl rollout restart deployment/app-no-constraints
kubectl rollout status deployment/app-no-constraints --timeout=60s
kubectl get deployment app-no-constraints -o jsonpath='{.spec.template.spec.topologySpreadConstraints}'
# result: now populated (zone + hostname constraints)

kubectl get policyreport -n default -o wide
# result (may take ~15s to appear): one report per Deployment, each with a
# pass/fail/skip count - app-no-constraints passes, app-soft-affinity and
# app-hard-affinity each show 1 fail. Doesn't say why.

kubectl get policyreport -n default -o yaml
# result: each report's results[] holds one entry per policy rule evaluated
# against that Deployment. app-soft-affinity and app-hard-affinity each carry
# a `result: fail` entry from report-unmanaged-scheduling-config, with the
# message text from validating-policy.yaml explaining why (their own
# scheduling config was left untouched)
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
