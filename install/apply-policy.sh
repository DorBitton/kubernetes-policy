#!/usr/bin/env bash
# Applies the zone-balance policies. Split out from setup.sh so you can
# deploy test apps against a bare cluster first, then apply policy
# afterward and see the mutation/validation take effect.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Applying zone-balance policies"
kubectl apply -f "$REPO_ROOT/cluster/policy/mutating-policy.yaml"
kubectl apply -f "$REPO_ROOT/cluster/policy/validating-policy.yaml"

echo "==> Done. Verify with: kubectl get clusterpolicy,validatingpolicy"
