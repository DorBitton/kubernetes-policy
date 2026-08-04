#!/usr/bin/env bash
# Sets up everything needed to reproduce this project locally:
# kind + helm (if missing) -> kind cluster -> Kyverno -> our policies.
# Safe to re-run: skips steps that are already done.
set -euo pipefail

CLUSTER_NAME="zone-policy"
KYVERNO_VERSION="3.8.2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Checking docker"
if ! command -v docker &>/dev/null || ! docker info &>/dev/null; then
  echo "docker is required, must be installed, and this user must be able to run it" >&2
  echo "(e.g. 'sudo usermod -aG docker \$USER' then log back in). Not automated here" >&2
  echo "since it can require a reboot/re-login - re-run this script once that's done." >&2
  exit 1
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

echo "==> Installing Kyverno ($KYVERNO_VERSION)"
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null
helm repo update >/dev/null
helm upgrade --install kyverno kyverno/kyverno \
  -n kyverno --create-namespace --version "$KYVERNO_VERSION" --wait

echo "==> Applying zone-balance policies"
kubectl apply -f "$REPO_ROOT/cluster/policy/mutating-policy.yaml"
kubectl apply -f "$REPO_ROOT/cluster/policy/validating-policy.yaml"

echo "==> Done. Verify with: kubectl get nodes -L topology.kubernetes.io/zone"
