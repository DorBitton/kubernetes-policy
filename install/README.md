# Install

## Prerequisites

- Docker, installed and usable by your user (`docker info` should work without
  `sudo`). If you just added yourself to the `docker` group, log out/in (or
  reboot) first — that part can't be scripted.

## Setup

```
./install/setup.sh
```

Safe to re-run — every step checks whether it's already done before doing it.
In order, it:

1. Checks Docker is usable, and warns if Docker's memory allocation looks too
   low to run kind + Kyverno reliably (below ~4GiB, installs can start timing
   out).
2. Installs `kind`, `kubectl`, and `helm`, skipping any that are already on
   your `PATH`.
3. Creates the local cluster from `cluster/kind-config.yaml`, skipped if a
   cluster with that name already exists.
4. Checks for a Kyverno Helm release left in a broken state by a previous
   failed run, and uninstalls it so the next step starts clean instead of
   erroring out.
5. Checks for Kyverno CRDs left behind with no matching Helm release (same
   cause — an aborted install), and removes them for the same reason.
6. Installs Kyverno via Helm.

It deliberately does **not** apply our policies — that's a separate step
(below), so you can deploy test apps against a bare cluster first if you
want to see the "before" state, then apply policy and see what changes.

Verify:

```
kubectl get nodes -L topology.kubernetes.io/zone
```

You should see one control-plane node and 4 worker nodes labeled
`zone-a`/`zone-a`/`zone-b`/`zone-c`.

## Manual installation

If you'd rather not run the script, or want to see exactly what it's doing,
here's the same setup by hand. Versions match `install/setup.sh` so the end
state is identical either way.

1. Install `kind` v0.32.0 — download the binary for your architecture from
   the [releases page](https://github.com/kubernetes-sigs/kind/releases/tag/v0.32.0)
   and put it on your `PATH`, e.g.:
   ```
   curl -Lo kind https://kind.sigs.k8s.io/dl/v0.32.0/kind-linux-amd64
   chmod +x kind && sudo mv kind /usr/local/bin/kind
   ```
2. Install `kubectl` — see the
   [official install docs](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/),
   or:
   ```
   curl -Lo kubectl "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl
   ```
3. Install `helm` 3.x — see the
   [official install docs](https://helm.sh/docs/intro/install/).
4. Create the cluster:
   ```
   kind create cluster --name zone-policy --config cluster/kind-config.yaml
   ```
5. Install Kyverno 3.8.2:
   ```
   helm repo add kyverno https://kyverno.github.io/kyverno/
   helm repo update
   helm upgrade --install kyverno kyverno/kyverno \
     -n kyverno --create-namespace --version 3.8.2 --wait --timeout 10m
   ```
6. Verify with the same command as above:
   `kubectl get nodes -L topology.kubernetes.io/zone`.

If a Kyverno install fails partway through, the manual equivalent of the
script's self-healing steps is: `helm uninstall kyverno -n kyverno`, then
`kubectl get crd | grep kyverno.io` and `kubectl delete crd <name>` for
anything left over before retrying step 5.

## Apply policy

```
./install/apply-policy.sh
```

Applies `cluster/policy/*.yaml`. Safe to re-run. Policies only affect
Deployments created or updated *after* they're applied — nothing already
running gets touched retroactively (see edge case 1 in the top-level README).

See `docs/testing.md` for the commands used to reproduce the edge-case demos,
and `docs/decisions.md` for why things are built the way they are.
