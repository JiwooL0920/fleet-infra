#!/bin/bash
set -e

helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update cilium

helm upgrade --install cilium cilium/cilium \
  --version 1.17.2 \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set operator.replicas=1 \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set k8sServiceHost=dev-services-amer-control-plane \
  --set k8sServicePort=6443 \
  --wait

kubectl rollout status daemonset/cilium -n kube-system --timeout=120s
echo "✅ Cilium bootstrapped successfully"
