#!/usr/bin/env bash
# Builds the local motion service environment: a conda env with Meta's
# Animated Drawings, TorchServe (with its own JDK, so nothing is installed
# system-wide) and the two model archives. Safe to re-run.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ENV_NAME=bogle-motion
VENDOR="$HERE/.vendor"
AD_REPO=https://github.com/facebookresearch/AnimatedDrawings.git
AD_COMMIT=b859684
MODELS=https://github.com/facebookresearch/AnimatedDrawings/releases/download/v0.0.1

mkdir -p "$VENDOR"
eval "$(conda shell.bash hook)"

if ! conda env list | grep -q "^$ENV_NAME "; then
  echo "*** Creating conda env $ENV_NAME (Python 3.8, arm64)"
  CONDA_SUBDIR=osx-arm64 conda create -y -n "$ENV_NAME" python=3.8.13
fi
conda activate "$ENV_NAME"
conda config --env --set subdir osx-arm64

echo "*** JDK for TorchServe (inside the env)"
conda install -y -c conda-forge openjdk=17

echo "*** Animated Drawings @ $AD_COMMIT"
[ -d "$VENDOR/AnimatedDrawings/.git" ] || git clone "$AD_REPO" "$VENDOR/AnimatedDrawings"
git -C "$VENDOR/AnimatedDrawings" checkout -q "$AD_COMMIT"
pip install -e "$VENDOR/AnimatedDrawings"

echo "*** Model server dependencies (versions from Meta's Dockerfile)"
pip install openmim torch==2.0.0 torchvision==0.15.1
# Xcode 16's clang rejects a specialization in torch 2.0's headers; keep it a
# warning so mmcv's native ops still build on Apple Silicon.
export CFLAGS="-Wno-invalid-specialization" CXXFLAGS="-Wno-invalid-specialization"
mim install mmcv-full==1.7.0
pip install mmdet==2.27.0
# mmpose needs xtcocotools; its build breaks under Cython 3.
pip install "cython<3"
pip install --no-build-isolation xtcocotools==1.14.3
pip install mmpose==0.29.0 numpy==1.24.4

echo "*** Service dependencies"
pip install -r "$HERE/requirements.txt"

echo "*** Models"
mkdir -p "$VENDOR/model-store"
for m in drawn_humanoid_detector drawn_humanoid_pose_estimator; do
  [ -s "$VENDOR/model-store/$m.mar" ] || curl -fL -o "$VENDOR/model-store/$m.mar" "$MODELS/$m.mar"
done

echo "*** Done. Start with: motion_server/run.sh"
