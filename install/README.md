# Install

## Prerequisites

- Docker, installed and usable by your user (`docker info` should work without
  `sudo`). If you just added yourself to the `docker` group, log out/in (or
  reboot) first — that part can't be scripted.

## Setup

```
./install/setup.sh
```

Safe to re-run. It will:

1. Install `kind` and `helm` if not already present.
2. Create the local cluster from `cluster/kind-config.yaml` (skipped if it
   already exists).
3. Install Kyverno via Helm.

It deliberately does **not** apply our policies — that's a separate step
(below), so you can deploy test apps against a bare cluster first if you
want to see the "before" state, then apply policy and see what changes.

Verify:

```
kubectl get nodes -L topology.kubernetes.io/zone
```

You should see one control-plane node and 4 worker nodes labeled
`zone-a`/`zone-a`/`zone-b`/`zone-c`.

## Apply policy

```
./install/apply-policy.sh
```

Applies `cluster/policy/*.yaml`. Safe to re-run. Policies only affect
Deployments created or updated *after* they're applied — nothing already
running gets touched retroactively (this is also edge case 1 in the
top-level README, not just a quirk of this script).

See `docs/testing.md` for the commands used to reproduce the edge-case demos,
and `docs/decisions.md` for why things are built the way they are.
