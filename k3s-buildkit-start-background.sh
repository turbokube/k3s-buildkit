#!/bin/sh
[ -z "$DEBUG" ] || set -x
set -eo pipefail

# Create directories
mkdir -p /var/lib/buildkit /run/buildkit /var/log/buildkit

echo "[k3s-buildkit] Waiting for k3s to be ready before starting buildkit..."

# Wait for k3s to be ready
until kubectl get nodes >/dev/null 2>&1; do
  sleep 1
done
echo "[k3s-buildkit] k3s is ready, starting buildkit..."

# Fixes warnings; maybe we should disable something instead
mkdir -p /var/run/cdi /etc/buildkit/cdi /etc/cdi

# Start buildkit
exec buildkitd --config /etc/buildkit/buildkitd.toml \
    > /var/log/buildkit/buildkitd.log 2>&1
