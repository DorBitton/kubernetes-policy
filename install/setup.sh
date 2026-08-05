#!/usr/bin/env bash
# Sets up the cluster and Kyverno, but does NOT apply our policies -
# see apply-policy.sh for that, kept separate so you can deploy test
# apps against a bare cluster first if you want to see the "before".
# kind + helm + kubectl (if missing) -> kind cluster -> Kyverno.
# Safe to re-run: skips steps that are already done, and recovers from
# a previous failed/partial Kyverno install.
set -euo pipefail

CLUSTER_NAME="zone-policy"
KYVERNO_VERSION="3.8.2"
KYVERNO_NAMESPACE="kyverno"
HELM_TIMEOUT="10m"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Checking docker"
if ! command -v docker &>/dev/null || ! docker info &>/dev/null; then
  echo "docker is required, must be installed, and this user must be able to run it" >&2
  echo "(e.g. 'sudo usermod -aG docker \$USER' then log back in). Not automated here" >&2
  echo "since it can require a reboot/re-login - re-run this script once that's done." >&2
  exit 1
fi

echo "==> Checking docker resources"
# kind + Kyverno's controllers are memory hungry on first boot; warn early
# rather than let helm --wait time out 10 minutes into the install.
docker_mem_bytes="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"
docker_mem_gb=$(( docker_mem_bytes / 1024 / 1024 / 1024 ))
if [ "$docker_mem_gb" -gt 0 ] && [ "$docker_mem_gb" -lt 4 ]; then
  echo "WARNING: Docker only sees ${docker_mem_gb}GiB of memory. Kyverno + kind" >&2
  echo "         can struggle below ~4GiB and cause 'context canceled' or TLS" >&2
  echo "         handshake timeouts during install. Consider raising the Docker/VM" >&2
  echo "         memory allocation before continuing." >&2
fi

echo "==> Installing kind"
if ! command -v kind &>/dev/null; then
  arch="$(uname -m)"
  case "$arch" in
    x86_64) kind_url="https://kind.sigs.k8s.io/dl/v0.32.0/kind-linux-amd64" ;;
    aarch64) kind_url="https://kind.sigs.k8s.io/dl/v0.32.0/kind-linux-arm64" ;;
    *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
  esac
  curl -Lo /tmp/kind "$kind_url"
  chmod +x /tmp/kind
  sudo mv /tmp/kind /usr/local/bin/kind
else
  echo "already installed: $(kind version)"
fi

echo "==> Installing kubectl"
if ! command -v kubectl &>/dev/null; then
  arch="$(uname -m)"
  case "$arch" in
    x86_64) kubectl_arch="amd64" ;;
    aarch64) kubectl_arch="arm64" ;;
    *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
  esac
  kubectl_version="$(curl -Ls https://dl.k8s.io/release/stable.txt)"
  curl -Lo /tmp/kubectl "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${kubectl_arch}/kubectl"
  chmod +x /tmp/kubectl
  sudo mv /tmp/kubectl /usr/local/bin/kubectl
else
  echo "already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
fi

echo "==> Installing helm"
if ! command -v helm &>/dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "already installed: $(helm version --short)"
fi

echo "==> Creating kind cluster ($CLUSTER_NAME)"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "cluster already exists, skipping"
else
  kind create cluster --name "$CLUSTER_NAME" --config "$REPO_ROOT/cluster/kind-config.yaml"
fi

echo "==> Checking for a stuck/failed prior Kyverno release"
# If a previous run got killed by a --wait timeout, the release can be left
# in 'pending-install'/'pending-upgrade'/'failed' state, and CRDs it half
# created can end up with ownership annotations that block a clean re-install.
# Parsed with grep/cut instead of jq to avoid a new dependency - fragile if
# `helm status -o json`'s formatting ever changes, but stable today.
existing_status="$(helm status kyverno -n "$KYVERNO_NAMESPACE" --output json 2>/dev/null | \
  grep -o '"status":"[a-z-]*"' | head -1 | cut -d'"' -f4 || true)"

if [ -n "$existing_status" ] && [ "$existing_status" != "deployed" ]; then
  echo "found kyverno release in '$existing_status' state, uninstalling before retry"
  if ! helm uninstall kyverno -n "$KYVERNO_NAMESPACE" --wait --timeout "$HELM_TIMEOUT"; then
    echo "WARNING: uninstalling the broken kyverno release failed - the reinstall" >&2
    echo "         below may fail too. Manual cleanup may be needed, e.g.:" >&2
    echo "         kubectl delete namespace $KYVERNO_NAMESPACE" >&2
  fi
fi

echo "==> Checking for orphaned Kyverno CRDs"
# CRDs from an aborted install can persist after the release is gone (or
# be owned by mismatched release metadata), which makes a fresh --install
# fail with an "invalid ownership metadata" error even though nothing is
# actually deployed. Deleting a CRD cascades to every CR of that type
# cluster-wide - fine here since this kind cluster is single-purpose, but
# not a pattern to copy onto a shared cluster.
orphaned_crds="$(kubectl get crd -o name 2>/dev/null | grep '\.kyverno\.io$' || true)"
if [ -n "$orphaned_crds" ] && [ -z "$(helm list -n "$KYVERNO_NAMESPACE" -f '^kyverno$' -o json 2>/dev/null | grep -o '"name"')" ]; then
  echo "found Kyverno CRDs with no matching helm release, removing them so install starts clean:"
  echo "$orphaned_crds"
  echo "$orphaned_crds" | xargs -r kubectl delete
fi

echo "==> Installing Kyverno ($KYVERNO_VERSION)"
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null
helm repo update >/dev/null
helm upgrade --install kyverno kyverno/kyverno \
  -n "$KYVERNO_NAMESPACE" --create-namespace --version "$KYVERNO_VERSION" \
  --wait --timeout "$HELM_TIMEOUT"

echo "==> Done. Cluster is ready, policies not yet applied."
echo "    Verify with: kubectl get nodes -L topology.kubernetes.io/zone"
echo "    Apply policies now with: ./install/apply-policy.sh"
