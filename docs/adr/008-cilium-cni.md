# ADR-008: Cilium as CNI

**Status:** Accepted
**Date:** 2026 (implemented), 2026-06 (documented as ADR)

## Context

Kind clusters use `kindnet` as the default CNI. It provides basic pod-to-pod networking but lacks:
- Network policy enforcement (beyond basic)
- eBPF-based observability (Hubble)
- kube-proxy replacement (performance)
- L7 visibility (HTTP-aware policies)

As the platform grows with security scanning (Kubescape), multi-agent communication (A2A), and observability requirements, a more capable CNI is needed.

## Decision

Deploy **Cilium** v1.17.x as the CNI with:
- `kubeProxyReplacement: true` — eBPF replaces kube-proxy for faster service routing
- `hubble.relay.enabled: true` — Network flow observability
- `hubble.ui.enabled: true` — Visual network topology
- `ipam.mode: kubernetes` — Use K8s-native IPAM

```yaml
values:
  kubeProxyReplacement: true
  hubble:
    relay:
      enabled: true
    ui:
      enabled: true
```

## Options Considered

1. **kindnet (default)** — Zero setup. But: no network policies, no observability, no eBPF benefits. Acceptable for trivial clusters, insufficient for security-focused platform.

2. **Calico** — Mature, well-documented. Good network policy support. But: no eBPF dataplane by default (requires separate install), no built-in Hubble-equivalent, heavier operator.

3. **Cilium** (chosen) — eBPF-native networking, Hubble observability, kube-proxy replacement, Gateway API support, identity-based policies. CNCF Graduated. Best fit for a platform that includes security scanning and needs L7 visibility.

4. **Flannel** — Lightweight overlay. No network policy at all. Not suitable.

## Consequences

### Positive

- **eBPF performance**: kube-proxy replacement eliminates iptables overhead for service routing
- **Hubble observability**: Real-time network flow visibility without tcpdump
- **Network policies**: L3/L4/L7 policies with identity-based enforcement
- **Gateway API**: Native support for future ingress migration from IngressRoute CRDs
- **Security agent integration**: Network flow data available for security-agent analysis

### Negative

- Requires disabling default CNI in Kind cluster config (`disableDefaultCNI: true`)
- Higher resource usage than kindnet (~100MB more RAM)
- eBPF requires Linux kernel 5.x+ (Colima provides this)
- More complex debugging when networking issues arise
- `k8sServiceHost`/`k8sServicePort` must be correctly configured for Kind

### Note on Kind Compatibility

Kind requires specific Cilium configuration:
- `cgroup.autoMount.enabled: false`
- `cgroup.hostRoot: /sys/fs/cgroup`
- Explicit `k8sServiceHost` pointing to control plane container name
