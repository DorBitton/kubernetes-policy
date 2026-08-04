# Kubernetes Policy — Zone-Balanced Scheduling

SRE take-home assignment: enforce zone-balanced pod scheduling on a local Kubernetes
cluster with minimum effort required from application developers. See `assignment.md`
for the original brief and `CLAUDE.md` for the working agreement used to build this.

## Status

- **Task 1 — local cluster: done.** `kind` cluster (`cluster/kind-config.yaml`), 4
  worker nodes labeled `topology.kubernetes.io/zone` (zone-a x2, zone-b, zone-c) plus a
  control-plane node. Asymmetric node-per-zone count is deliberate — with 1 node per
  zone, "spread across nodes" and "spread across zones" are indistinguishable, which
  would hide bugs in zone-aware policy later.
- **Task 2 — policy engine: in progress.** Kyverno, installed via Helm (see
  `install/README.md`). Mutating + validating policy for Deployments done and tested
  (zone + hostname spread injection, minimum-3 replicas floor, scoped to application
  namespaces). StatefulSets deliberately excluded, pending a dedicated policy.

Two different Kyverno policy kinds are in use on purpose, not out of inconsistency —
mutation is stuck on the deprecated `ClusterPolicy` engine because of real bugs in
Kyverno's newer CEL-based `MutatingPolicy`, while validation uses the modern
`ValidatingPolicy` since it doesn't hit those bugs. See `docs/decisions.md` for the
full reasoning and pros/cons behind this and every other non-obvious call made on this
project.

## Repo layout

- `cluster/kind-config.yaml` — cluster topology definition.
- `cluster/policy/mutating-policy.yaml` — Kyverno `ClusterPolicy`: injects zone +
  hostname `topologySpreadConstraints` and enforces a minimum-3-replicas floor on
  Deployments that don't already define their own scheduling config.
- `cluster/policy/validating-policy.yaml` — Kyverno `ValidatingPolicy`: audits (never
  rejects) Deployments the mutating policy backed off from.
- `install/README.md` + `install/setup.sh` — prerequisites and a script that installs
  kind/helm/Kyverno and creates the cluster (deliberately does not apply policy).
- `install/apply-policy.sh` — applies `cluster/policy/*.yaml`, kept separate from setup
  so you can deploy test apps against a bare cluster first and see the "before".
- `test-apps/` — fixture Deployments used to probe scheduling edge cases:
  - `app-no-constraints/` — baseline, no scheduling config at all.
  - `app-soft-affinity/` — preferred (soft) nodeAffinity toward zone-a.
  - `app-hard-affinity/` — required (hard) nodeAffinity to zone-a only.
- `docs/decisions.md` — why things are built the way they are, pros and cons.
- `docs/testing.md` — exact commands to reproduce the edge-case demos below.
- `CLAUDE.md` — collaboration ground rules for working on this repo with an LLM agent.

## Edge cases identified for task 2

Before picking an enforcement mechanism, we identified and (where possible) empirically
demonstrated 5 edge cases the policy needs to survive:

1. **Capacity added after pods are already scheduled.** Demonstrated: cordon zone-b/c,
   deploy `app-no-constraints` (all 6 pods land zone-a), uncordon — pods do not move.
   Kubernetes never proactively rebalances already-running pods.
2. **Capacity lost while pods are already running** (simulated AZ outage). Demonstrated:
   drain a zone-b node mid-run — its pods reschedule onto remaining zones (3/0/3), and
   stay that way after zone-b is restored. Same non-rebalancing behavior as case 1, from
   the other direction.
3. **Developer manifest with a soft (preferred) scheduling constraint that conflicts
   with zone balance.** Demonstrated via `app-soft-affinity`: a single
   `preferredDuringSchedulingIgnoredDuringExecution` term with weight 100 fully
   dominated the scheduler's built-in default zone-spread scoring — all 6 pods landed
   in zone-a. Since it's advisory, a policy can safely override it.
4. **Developer manifest with a hard (required) scheduling constraint.** Demonstrated via
   `app-hard-affinity`: `requiredDuringSchedulingIgnoredDuringExecution` filters out all
   nodes outside zone-a before scoring even runs — a policy cannot safely override this
   without risking breaking a real requirement, so the correct behavior is to validate
   and report, not silently mutate.
5. **StatefulSets with `volumeClaimTemplate`.** Not demonstrable locally — kind's
   default StorageClass (local-path-provisioner) isn't zone-aware, unlike real EBS on
   EKS which zone-locks a PV permanently once bound. To be covered in written docs only:
   a policy cannot rebalance a stateful pod across zones after its PVC is bound, no
   matter the enforcement mechanism.

## Reproducing this state

Run `install/setup.sh`, then `install/apply-policy.sh` (see `install/README.md`).
`docs/testing.md` has the commands used for the edge-case demos above.

## Current cluster state

As of the last session: cluster recreated with the 4-node/3-zone topology, all nodes
uncordoned and `Ready`, baseline + edge-case fixtures deployed. Clean starting point for
task 2 work.
