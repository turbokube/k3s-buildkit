#!/bin/sh
[ -z "$DEBUG" ] || set -x
set -eo pipefail

echo "[k3d-buildkit k3d entrypoint] Starting buildkitd for k3d..."

k3s-buildkit-start-background.sh 2>/var/log/k3s-buildkit.err | tee /var/log/k3s-buildkit.log &
