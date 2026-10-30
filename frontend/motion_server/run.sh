#!/usr/bin/env bash
# Starts TorchServe (the two drawing models) and the motion API.
#   motion_server/run.sh            # API on 0.0.0.0:8000, reachable from an iPad on the same Wi-Fi
#   PORT=9000 motion_server/run.sh
set -euo pipefail
cd "$(dirname "$0")"
eval "$(conda shell.bash hook)"
conda activate bogle-motion
mkdir -p data

if ! curl -s http://127.0.0.1:8080/ping | grep -q Healthy; then
  echo "*** Starting TorchServe"
  torchserve --start --ncs --disable-token-auth --ts-config torchserve.properties > data/torchserve.log 2>&1
  for _ in $(seq 1 60); do
    curl -s http://127.0.0.1:8080/ping | grep -q Healthy && break
    sleep 2
  done
fi
trap 'torchserve --stop >/dev/null 2>&1 || true' EXIT

IP=$(ipconfig getifaddr en0 2>/dev/null || echo 127.0.0.1)
echo "*** Motion API: http://$IP:${PORT:-8000}  (build the app with --dart-define=MOTION_SERVER=http://$IP:${PORT:-8000})"
uvicorn app:app --host 0.0.0.0 --port "${PORT:-8000}"
