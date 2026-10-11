#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

cert_dir=$(mktemp -d)
trap 'rm -rf "$cert_dir"' EXIT

(
  cd "$cert_dir"
  MSYS_NO_PATHCONV=1 openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout tls.key -out tls.crt \
    -subj '/CN=prometheus-adapter.default.svc' \
    -addext 'subjectAltName=DNS:prometheus-adapter.default.svc,DNS:prometheus-adapter.default.svc.cluster.local'
)

kubectl -n default create secret tls prometheus-adapter-tls \
  --cert="$cert_dir/tls.crt" --key="$cert_dir/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f prometheus.yaml -f prometheus-adapter.yaml

ca_bundle=$(base64 < "$cert_dir/tls.crt" | tr -d '\n')
kubectl patch apiservice v1beta1.custom.metrics.k8s.io --type=merge \
  -p "{\"spec\":{\"caBundle\":\"$ca_bundle\"}}"

kubectl rollout restart deployment/prometheus-adapter
kubectl rollout status deployment/prometheus --timeout=180s
kubectl rollout status deployment/prometheus-adapter --timeout=180s
kubectl wait apiservice/v1beta1.custom.metrics.k8s.io \
  --for=condition=Available --timeout=180s