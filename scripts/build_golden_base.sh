#!/bin/bash
# ==============================================================================
# Tier 1 Golden Base RootFS Builder & OCI Packager
# ==============================================================================
# Synthesizes the Ubuntu 24.04 (Noble) + ROS 2 Jazzy Foundation RootFS.
# Excludes the 10 Ubiquity application debians so the resulting artifact
# is immutable, cacheable, and reusable for sub-5-minute Tier 2 builds.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

cd "$REPO_ROOT"

CONFIG="config/ubuntu24-ros2-pi5.cfg"
OPTIONS="credentials24"
OUTPUT_DIR="work/ros2/deploy"
IMAGE_TAG="ghcr.io/ubiquityrobotics/magni-base-rootfs:noble-jazzy"
PUSH_GHCR=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      CONFIG="$2"
      shift 2
      ;;
    -o|--options)
      OPTIONS="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --push-ghcr)
      PUSH_GHCR=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo "  -c, --config <file>     Config file (default: config/ubuntu24-ros2-pi5.cfg)"
      echo "  -o, --options <file>    Options file (default: credentials24)"
      echo "      --output-dir <dir>  Output directory (default: work/ros2/deploy)"
      echo "      --tag <tag>         OCI container tag (default: ghcr.io/ubiquityrobotics/magni-base-rootfs:noble-jazzy)"
      echo "      --push-ghcr         Push OCI container to GitHub Container Registry"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

echo "=========================================================="
echo "      SYNTHESIZING TIER 1 GOLDEN BASE ROOTFS (ARM64)     "
echo "=========================================================="
echo "Config profile : $CONFIG"
echo "Options file   : $OPTIONS"
echo "Target Tag     : $IMAGE_TAG"
echo "Output dir     : $OUTPUT_DIR"
echo "=========================================================="

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"
mkdir -p work/ros2/rootfs

# Instruct Ansible to provision only base OS, kernel, networking, and systemd services
export ANSIBLE_EXTRA_VARS="-e build_tier=base"
export SKIP_AUTOMATED_TESTS=1

# Synthesize rootfs via bdebstrap
./build.sh -r -c "$CONFIG" -o "$OPTIONS"

ROOTFS="work/ros2/rootfs"

echo "[INFO] Cleaning ephemeral caches and build-time state from base rootfs..."
podman unshare rm -rf \
  "${ROOTFS}/var/cache/apt/archives/"* \
  "${ROOTFS}/var/lib/apt/lists/"* \
  "${ROOTFS}/tmp/"* \
  "${ROOTFS}/var/tmp/"* \
  "${ROOTFS}/etc/machine-id" \
  "${ROOTFS}/var/lib/dbus/machine-id" || true

# Recreate empty machine-id files
podman unshare touch "${ROOTFS}/etc/machine-id"

TARBALL="${OUTPUT_DIR}/magni-base-noble-jazzy.tar.zst"
echo "[INFO] Exporting Tier 1 RootFS to high-ratio zstd archive: $TARBALL ..."
podman unshare tar --numeric-owner -I 'zstd -T0 -19' -cf "$TARBALL" -C "$ROOTFS" .

echo "[INFO] Generating SHA256 checksum for base rootfs tarball..."
sha256sum "$TARBALL" | awk '{print $1}' > "${TARBALL}.sha256"

echo "[INFO] Packaging OCI container image: $IMAGE_TAG ..."
podman import "$ROOTFS" "$IMAGE_TAG"

if [ "$PUSH_GHCR" = true ]; then
  echo "[INFO] Pushing OCI container image to GHCR ($IMAGE_TAG)..."
  podman push "$IMAGE_TAG"
fi

echo "=========================================================="
echo "   TIER 1 GOLDEN BASE ROOTFS READY FOR INSTANT REUSE!    "
echo "=========================================================="
echo "Archive Tarball : $TARBALL ($(du -h "$TARBALL" | cut -f1))"
echo "Checksum        : $(cat "${TARBALL}.sha256")"
echo "Container Image : $IMAGE_TAG"
echo "=========================================================="
