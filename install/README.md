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
4. Apply our policies (`cluster/policy/*.yaml`).

Verify:

```
kubectl get nodes -L topology.kubernetes.io/zone
```

You should see one control-plane node and 4 worker nodes labeled
`zone-a`/`zone-a`/`zone-b`/`zone-c`.

See `docs/testing.md` for the commands used to reproduce the edge-case demos,
and `docs/decisions.md` for why things are built the way they are.
