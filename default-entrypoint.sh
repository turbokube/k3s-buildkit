#!/bin/sh
[ -z "$DEBUG" ] || set -x
set -eo pipefail

k3s-buildkit-start-background.sh 2>/var/log/k3s-buildkit.err | tee /var/log/k3s-buildkit.log &

exec /bin/k3s "$@"
