# Decisions

Short log of the non-obvious calls made on this project, and why. Format per
entry: what we chose, why, pros, cons.

## Local cluster: kind

**Why:** closest local equivalent to EKS — its config file lets us declare
per-node `topology.kubernetes.io/zone` labels directly, the same label EKS's
cloud-controller-manager sets on real nodes.
**Pros:** zero-translation compatibility with real zone-aware K8s APIs; one
declarative config file; no cloud cost.
**Cons:** all "nodes" are containers on one Docker host — no real network/AZ
failure domains, so only the scheduling mechanics can be tested, not real
zone outages.

## Asymmetric node count per zone (zone-a x2, zone-b x1, zone-c x1)

**Why:** with exactly 1 node per zone, "spread across nodes" and "spread
across zones" look identical, which would hide a bug where a policy is
keyed on the wrong label.
**Pros:** makes node-spread vs zone-spread distinguishable in test output.
**Cons:** not a symmetric, realistic-looking topology; more nodes on a
single dev machine than the minimum needed.

## Kyverno as the policy engine

**Why:** native Kubernetes CRDs, no custom webhook server to write/run/secure
ourselves, large community policy library to reference.
**Pros:** fast to iterate; well-documented; both mutate and validate in one
tool.
**Cons:** turned out to have real bugs in its newest policy engine (see
below) — cost significant time to isolate and work around.

## Mutating policy: classic `ClusterPolicy`, not the CEL-based `MutatingPolicy`

**Why:** `MutatingPolicy` was tried first and ruled out — both its
`patchType` options fail to inject a `topologySpreadConstraints` entry that
includes a `labelSelector`. Confirmed as Kyverno engine bugs, not real
Kubernetes API limits (an identical raw `kubectl patch` succeeds). Full
detail in `cluster/policy/mutating-policy.yaml`.
**Pros:** works, tested against the live cluster.
**Cons:** `ClusterPolicy` is deprecated (removal targeted Kyverno v1.20,
~Oct 2026) — this is a known-temporary fallback, not the intended long-term
approach.

## Validating policy: modern `ValidatingPolicy` (CEL), not `ClusterPolicy`

**Why:** the `MutatingPolicy` bugs above are specific to constructing a
mutation patch. A validating rule only evaluates a boolean expression, so it
doesn't hit the same wall — confirmed empirically before switching.
**Pros:** not on a deprecated engine; cleaner CEL syntax than JMESPath.
**Cons:** two different policy engines in one project is one more thing to
explain/maintain.

## Mutate where safe, report (never reject) where not

**Why:** treated as a staging-like environment for now, not prod — a QA
cluster should never block a deploy over this, prod might. Reporting without
blocking is the middle ground.
**Pros:** never breaks a developer's deploy; still gives visibility into
what isn't auto-balanced.
**Cons:** a genuinely misconfigured Deployment can still go live unbalanced
if nobody reads the policy report.

## Mutation backs off from *any* pre-existing scheduling config, not just hard constraints

**Why:** simpler and safer than trying to distinguish "safe to override"
(soft/preferred) from "must not override" (hard/required) inside the
mutation logic itself.
**Pros:** never silently overrides a developer's intent, even a soft one.
**Cons:** a soft/preferred constraint we could have safely fixed is instead
just left alone and reported — less automatic balancing than technically
possible.

## Two `topologySpreadConstraints`: zone and hostname

**Why:** zone spread alone still allows multiple replicas to land on the
same node within a zone — still a single point of failure. Matches
Kubernetes' own built-in default constraints, which do both.
**Pros:** better real resilience per replica, not just per zone.
**Cons:** one more constraint to reason about when things don't spread as
expected.

## Minimum replicas: floor of 3, no exemptions, only on the Deployment resource (not `/scale`)

**Why:** zone spread is meaningless below 3 replicas. Not exempting 0
because this policy is treated as prod. Not matching the `/scale`
subresource because `kubectl scale`/HPA changes are informed operational
decisions by someone who already knows the tradeoffs — the policy exists to
help developers who never thought about zones/HA at all, not to fight a
deliberate scale action.
**Pros:** closes the "just write nothing" gap without fighting legitimate
ops workflows.
**Cons:** a developer relying on `kubectl apply` to scale down to 1 or 2
(instead of `kubectl scale`) will get overridden — the policy can't tell
those two intents apart.

## `zone-policy.io/managed-spread` annotation marker

**Why:** mutating webhooks run before validating ones in the same request,
so by the time validation runs, a Deployment we just auto-balanced looks
identical (has `topologySpreadConstraints`) to one with a developer's own
pre-existing config. The annotation is the only way to tell them apart.
**Pros:** validation report is accurate — only flags genuinely unmanaged
config, not our own work.
**Cons:** couples the two policies together — the validating policy is only
correct as long as the mutating policy keeps stamping this annotation.

## Namespace scoping: exclude system namespaces

**Why:** without it, `kube-system` (coredns), the `kyverno` namespace
itself, and `local-path-storage` were being matched — mutating
cluster-critical infrastructure was never the intent.
**Pros:** blast radius limited to actual application workloads.
**Cons:** exclusion list is maintained by name, not a label selector on app
namespaces — a new system namespace added later needs to be added here too.

## StatefulSets excluded for now

**Why:** a `volumeClaimTemplate`-backed pod's PVC zone-locks to a real EBS
volume on a real EKS cluster once bound — the pod can never move zones
again after that, no matter what a policy does. This needs different
handling than Deployments, not just the same mutation with a wider resource
match. See edge case 5 in the top-level README for detail; kind's
local-path-provisioner can't even demonstrate the zone-lock locally since it
isn't zone-aware.
**Pros:** avoids shipping a policy that mutates StatefulSets in a way that
looks like it works locally but is wrong on real EKS.
**Cons:** StatefulSet zone-balance is currently just undone — no policy,
no report, until the dedicated policy is built.
