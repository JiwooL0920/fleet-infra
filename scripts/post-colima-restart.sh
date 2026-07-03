#!/usr/bin/env bash
set -euo pipefail

if [[ "${DEBUG:-0}" == "1" ]]; then
  set -x
fi

echo "Fixing control plane IP configuration after Colima restart..."
./scripts/fix-control-plane-ip.sh

./scripts/refresh-credentials.sh

echo ""
echo "🧹 Cleaning up failed jobs from restart window..."
kubectl delete job create-grafana-sa-token -n monitoring --ignore-not-found=true 2>/dev/null || true
echo ""
echo "⏳ Waiting for Grafana to be healthy..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=120s 2>/dev/null || \
  echo "⚠️  Grafana not ready yet — grafana-sa-setup may need manual reconcile later"
echo ""
echo "🔄 Reconciling grafana-sa-setup (creates SA token for kagent)..."
flux reconcile kustomization grafana-sa-setup --timeout=3m 2>/dev/null || \
  echo "⚠️  grafana-sa-setup reconcile timed out — retry with: flux reconcile kustomization grafana-sa-setup"
echo ""
if [[ -n "${GITHUB_TOKEN:-}" || -n "${GITHUB_PAT:-}" ]]; then
  echo "🔑 Detected GitHub token in environment. Re-syncing GitHub secret..."
  ./scripts/init-github-secret.sh
else
  echo "💡 Tip: Run 'make setup-github-secret' if you use the gitops-agent (requires GitHub PAT)."
fi
echo ""
echo "🦙 Checking native Ollama (needed for kagent)..."
if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
  echo "  ✅ Ollama is running"
else
  echo "  ⚠️  Ollama is not running. Start with: make serve-ollama"
fi
echo ""
echo "📊 Final kustomization health:"
flux get kustomizations 2>/dev/null | grep -E "False|Unknown" | grep -v "ollama" || \
  echo "  ✅ All kustomizations healthy (ollama intentionally suspended)"
echo ""
echo "✅ Post-Colima restart setup completed!"
echo "   Run 'make get-ui-credentials' for login credentials."
