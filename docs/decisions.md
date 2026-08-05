# Decisions

## Install split into setup.sh and apply-policy.sh

Applying policy is a separate step from standing up the cluster, so you can deploy test
apps against a bare cluster first and see the "before" state, then apply policy and see
exactly what changes.

## Local cluster: kind

Closest local match to EKS — its config lets us set per-node
`topology.kubernetes.io/zone` labels directly, the same label EKS's
cloud-controller-manager sets on real nodes. Downside: all "nodes" are containers on one
Docker host, so only the scheduling mechanics are testable, not a real zone outage.

## Asymmetric node count per zone (zone-a x2, zone-b x1, zone-c x1)

With one node per zone, "spread across nodes" and "spread across zones" look identical —
that would hide a policy that's keyed on the wrong label. Less tidy topology, but the two
failure modes are distinguishable in test output.

## Mutating policy: classic ClusterPolicy, not the CEL-based MutatingPolicy

`MutatingPolicy` was tried first and ruled out — both its `patchType` options fail to
inject a `topologySpreadConstraints` entry that includes a `labelSelector`. Confirmed as
Kyverno engine bugs, not real Kubernetes API limits (an identical raw `kubectl patch`
works fine). `ClusterPolicy` is deprecated (removal targeted Kyverno v1.20, ~Oct 2026),
so this is a known-temporary fallback, not the intended long-term approach. Detail in
`cluster/policy/mutating-policy.yaml`.

## Validating policy: modern ValidatingPolicy (CEL), not ClusterPolicy

The `MutatingPolicy` bugs above are specific to constructing a mutation patch. A
validating rule only evaluates a boolean expression, so it doesn't hit the same wall —
confirmed against the live cluster before switching. Trade-off: two different policy
engines in one project is one more thing to explain.

## Mutate where safe, report (never reject) where not

Treated as a staging-like environment for now - shouldn't block a deploy over
this. Reporting without blocking is the middle ground; it also means a genuinely
unbalanced Deployment can still go live if nobody reads the report.

## Mutation backs off from any pre-existing scheduling config, not just hard constraints

Simpler and safer than trying to distinguish "safe to override" (soft/preferred) from
"must not override" (hard/required) inside the mutation logic itself. Never silently
overrides a developer's intent — but a soft constraint we could have safely fixed is
instead just left alone and reported.

## Two topologySpreadConstraints: zone and hostname

Zone spread alone still allows multiple replicas to land on the same node within a zone
— still a single point of failure. Matches Kubernetes' own built-in default constraints,
which spread on both.

## Minimum replicas: floor of 3, no exemptions, Deployment resource only (not /scale)

Doesn't match the `/scale` subresource because `kubectl scale`/HPA changes are a deliberate operational decision, not a developer's default manifest that never considered zones — fighting that isn't this policy's job.
Trade-off: a developer relying on `kubectl apply` to scale down (instead of
`kubectl scale`) gets overridden anyway.

## zone-policy.io/managed-spread annotation marker

Mutating webhooks run before validating ones in the same request, so by the time
validation runs, a Deployment we just auto-balanced looks identical to one with a
developer's own pre-existing config — both have `topologySpreadConstraints`. The
annotation is the only way to tell them apart. Trade-off: couples the two policies —
validation is only accurate as long as mutation keeps stamping it.

## Namespace scoping: exclude system namespaces

The exclusion list is maintained by name, not a label selector, so a new system namespace added later needs to be added here too. (Not ideal)

## StatefulSets: documented, not policy-enforced

A `volumeClaimTemplate`-backed pod's PVC zone-locks to a real EBS volume on EKS the
first time it's provisioned (`WaitForFirstConsumer`), and the PV carries that zone as a
`nodeAffinity` from then on. The pod can never move zones again after that, no matter
what a policy does — a `topologySpreadConstraint` has no power over a pod whose volume
is already bound. Also not demonstrable locally — kind's local-path-provisioner isn't zone-aware, so the zone-lock can't even be shown on this cluster. See edge case 5 in the README. Trade-off: StatefulSet zone-balance gets no automated help at all, only this write-up.
