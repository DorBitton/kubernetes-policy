apt update
apt upgrade

required: docker

kind
# For AMD64 / x86_64
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.32.0/kind-linux-amd64
# For ARM64
[ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.32.0/kind-linux-arm64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind


sudo usermod -aG docker $USER

sudo reboot

groups = should have docker


create cluster:
    kind create cluster --name zone-policy --config cluster/kind-config.yaml

recreate cluster after kind-config.yaml changes (kind can't hot-add nodes):
    kind delete cluster --name zone-policy
    kind create cluster --name zone-policy --config cluster/kind-config.yaml

check node/zone labels:
    kubectl get nodes -L topology.kubernetes.io/zone

deploy baseline test app (no scheduling constraints):
    kubectl apply -f test-apps/app-no-constraints/deployment.yaml
    kubectl get pods -l app=app-no-constraints -o wide

deploy test app with soft (preferred) zone affinity - case 3, policy-fixable:
    kubectl apply -f test-apps/app-soft-affinity/deployment.yaml
    kubectl get pods -l app=app-soft-affinity -o wide

deploy test app with hard (required) zone affinity - case 4, report-only:
    kubectl apply -f test-apps/app-hard-affinity/deployment.yaml
    kubectl get pods -l app=app-hard-affinity -o wide

edge case 1 - capacity added after pods already scheduled:
    kubectl cordon zone-policy-worker3
    kubectl cordon zone-policy-worker4
    kubectl rollout restart deployment/app-no-constraints
    kubectl rollout status deployment/app-no-constraints --timeout=60s
    kubectl get pods -l app=app-no-constraints -o wide
    # result: all 6 replicas land on zone-a (only uncordoned zone)
    kubectl uncordon zone-policy-worker3
    kubectl uncordon zone-policy-worker4
    kubectl get pods -l app=app-no-constraints -o wide
    # result: unchanged, pods stay on zone-a - no automatic rebalance when capacity returns

edge case 2 - capacity lost while pods already running (simulated AZ outage):
    # first reset to a balanced baseline (all zones schedulable)
    kubectl rollout restart deployment/app-no-constraints
    kubectl rollout status deployment/app-no-constraints --timeout=60s
    kubectl get pods -l app=app-no-constraints -o wide
    # then drain the zone-b node while its pods are running
    kubectl drain zone-policy-worker3 --ignore-daemonsets --delete-emptydir-data --force
    kubectl get pods -l app=app-no-constraints -o wide
    # result: evicted pods reschedule onto remaining zones (zone-a/zone-c), e.g. 3/0/3
    kubectl uncordon zone-policy-worker3
    kubectl get pods -l app=app-no-constraints -o wide
    # result: unchanged - no automatic rebalance back once zone-b returns

cleanup leftover Completed pods from rollout restarts:
    kubectl delete pods -l app=app-no-constraints --field-selector=status.phase=Succeeded


helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash


kyverno 3.8.2
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno -n kyverno --create-namespace --version 3.8.2

