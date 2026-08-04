# Kubernetes Policy — Zone-Balanced Scheduling

SRE take-home assignment: enforce zone-balanced pod scheduling on a local Kubernetes
cluster with minimum effort required from application developers. See `assignment.md`
for the original brief and `CLAUDE.md` for the working agreement used to build this.

## Status

- **Task 1 — local cluster: done.** `kind` cluster (`cluster/kind-config.yaml`), 4
  worker nodes labeled `topology.kubernetes.io/zone` (zone-a x2, zone-b, zone-c) plus a
  control-plane node. Node count per zone is asymmetric on purpose — see
  `docs/decisions.md`.
- **Task 2 — policy engine: done.** Kyverno, installed via Helm (see
  `install/README.md`). Mutating + validating policy for Deployments (zone + hostname
  spread injection, minimum-3 replicas floor, scoped to application namespaces).
  StatefulSets are out of scope by design — see edge case 5 below for why.

Two different Kyverno policy kinds are in use: mutation on the deprecated
`ClusterPolicy` engine, validation on the newer `ValidatingPolicy`. Reasoning in
`docs/decisions.md`.

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

## Edge cases for task 2

5 edge cases the policy needs to survive, demonstrated where possible:

1. **Capacity added after pods are already scheduled.** Cordon zone-b/c, deploy
   `app-no-constraints` (all 6 pods land in zone-a), uncordon — pods don't move.
   Kubernetes never proactively rebalances already-running pods.
2. **Capacity lost while pods are running** (simulated AZ outage). Drain a zone-b node
   mid-run — its pods reschedule onto remaining zones (3/0/3), and stay that way after
   zone-b comes back. Same non-rebalancing behavior as case 1, other direction.
3. **Soft (preferred) scheduling constraint conflicting with zone balance.**
   `app-soft-affinity`'s single preferred term (weight 100) fully dominated the
   scheduler's default zone-spread scoring — all 6 pods landed in zone-a. It's advisory,
   so a policy can safely override it.
4. **Hard (required) scheduling constraint.** `app-hard-affinity`'s required term
   filters out all nodes outside zone-a before scoring even runs. A policy can't safely
   override this without risking a real requirement, so the correct behavior is to
   report, not mutate.
5. **StatefulSets with `volumeClaimTemplate`.** Not demonstrable locally — kind's
   local-path-provisioner isn't zone-aware, unlike real EBS on EKS, which zone-locks a
   PV to the AZ it was first provisioned in. Once that PVC is bound, the pod can never
   move zones again — no scheduling policy, mutating or otherwise, can undo it. That's
   why StatefulSets are handled here in writing only, not with a policy: there's nothing
   for a policy to enforce after the fact. See `docs/decisions.md` for detail.

## Reproducing this state

Run `install/setup.sh`, then `install/apply-policy.sh` (see `install/README.md`).
`docs/testing.md` has the commands used for the edge-case demos above.
