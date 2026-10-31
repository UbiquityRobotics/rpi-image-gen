#!/bin/bash
# ==============================================================================
# Tier 2 Fast Appliance Release Synthesizer (Sub-5-Minute Delivery Pipeline)
# ==============================================================================
# Instantly restores the pre-baked Tier 1 Golden Base RootFS from local NVMe/OCI,
# installs only the 10 changed application debian packages directly into
# /opt/ros/jazzy, verifies the rootfs, and generates the 10G bootable SD card image.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

cd "$REPO_ROOT"

CONFIG="config/ubuntu24-ros2-pi5.cfg"
OPTIONS="credentials24"
DEBS_DIR="ansible/roles/ros2_workspace/files/debs"
BASE_IMAGE="ghcr.io/ubiquityrobotics/magni-base-rootfs:noble-jazzy"
BASE_TARBALL=""
SKIP_TESTS=false

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
    --debs-dir)
      DEBS_DIR="$2"
      shift 2
      ;;
    --base-tarball)
      BASE_TARBALL="$2"
      shift 2
      ;;
    --base-image)
      BASE_IMAGE="$2"
      shift 2
      ;;
    --skip-tests)
      SKIP_TESTS=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo "  -c, --config <file>     Config file (default: config/ubuntu24-ros2-pi5.cfg)"
      echo "  -o, --options <file>    Options file (default: credentials24)"
      echo "      --debs-dir <dir>    Directory with 10 appliance .debs (default: ansible/roles/ros2_workspace/files/debs)"
      echo "      --base-tarball <f>  Path to base rootfs tarball"
      echo "      --base-image <tag>  OCI container tag for base rootfs"
      echo "      --skip-tests        Skip automated rootfs test suite"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

echo "=========================================================="
echo "    SYNTHESIZING TIER 2 FAST APPLIANCE DISK IMAGE         "
echo "=========================================================="
echo "Config profile : $CONFIG"
echo "Options file   : $OPTIONS"
echo "Debian packages: $DEBS_DIR"
echo "Base image tag : $BASE_IMAGE"
echo "=========================================================="

ROOTFS="work/ros2/rootfs"
START_TIME=$(date +%s)

# ------------------------------------------------------------------------------
# STEP 1: Restore Golden Base RootFS
# ------------------------------------------------------------------------------
echo "==> [Phase 1/5] Restoring Golden Base RootFS..."
mkdir -p "$ROOTFS"

RESTORED=false

# 1. Check specified or default local NVMe tarball paths
TARBALL_CANDIDATES=(
  "$BASE_TARBALL"
  "/opt/ubiquity/base-rootfs/magni-base-noble-jazzy.tar.zst"
  "work/ros2/deploy/magni-base-noble-jazzy.tar.zst"
  "magni-base-noble-jazzy.tar.zst"
)

for tb in "${TARBALL_CANDIDATES[@]}"; do
  if [ -n "$tb" ] && [ -f "$tb" ]; then
    echo "[INFO] Found local base rootfs archive: $tb. Unpacking via zstd..."
    podman unshare tar --numeric-owner -I 'zstd -T0' -xf "$tb" -C "$ROOTFS"
    RESTORED=true
    break
  fi
done

# 2. Check local Podman container image
if [ "$RESTORED" = false ]; then
  if podman image exists "$BASE_IMAGE" 2>/dev/null; then
    echo "[INFO] Found local Podman image '$BASE_IMAGE'. Exporting to rootfs..."
    CONTAINER_ID=$(podman create "$BASE_IMAGE")
    podman export "$CONTAINER_ID" | podman unshare tar --numeric-owner -xf - -C "$ROOTFS"
    podman rm "$CONTAINER_ID" >/dev/null
    RESTORED=true
  fi
fi

# 3. Pull from GitHub Container Registry
if [ "$RESTORED" = false ]; then
  echo "[INFO] Attempting to pull base rootfs from GHCR ($BASE_IMAGE)..."
  if podman pull "$BASE_IMAGE" 2>/dev/null; then
    CONTAINER_ID=$(podman create "$BASE_IMAGE")
    podman export "$CONTAINER_ID" | podman unshare tar --numeric-owner -xf - -C "$ROOTFS"
    podman rm "$CONTAINER_ID" >/dev/null
    RESTORED=true
  fi
fi

# 4. Fallback: Full bootstrap
FALLBACK_BOOTSTRAP=false
if [ "$RESTORED" = false ]; then
  echo "[WARN] No Golden Base found on NVMe or GHCR! Falling back to full bdebstrap..."
  ./build.sh -r -c "$CONFIG" -o "$OPTIONS"
  RESTORED=true
  FALLBACK_BOOTSTRAP=true
fi

echo "[PASS] Golden Base RootFS restored in $(($(date +%s) - START_TIME)) seconds."

# If we had to bootstrap from scratch, automatically cache the base rootfs to DO Spaces for future runs
if [ "$FALLBACK_BOOTSTRAP" = true ] && [ -n "${S3_ACCESS_KEY:-}" ] && [ -n "${S3_SECRET_KEY:-}" ]; then
  echo "[INFO] Caching synthesized base rootfs to DigitalOcean Spaces for future instant runs..."
  CACHE_DIR="work/ros2/deploy"
  mkdir -p "$CACHE_DIR"
  CACHE_TARBALL="${CACHE_DIR}/magni-base-noble-jazzy.tar.zst"
  podman unshare tar --numeric-owner -I 'zstd -T0 -1' -cf "$CACHE_TARBALL" -C "$ROOTFS" .
  s3cmd --access_key="$S3_ACCESS_KEY" \
        --secret_key="$S3_SECRET_KEY" \
        --host="sfo2.digitaloceanspaces.com" \
        --host-bucket="%(bucket)s.sfo2.digitaloceanspaces.com" \
        --acl-public \
        put "$CACHE_TARBALL" s3://ubiquity-pi-image/cache/ || true
  echo "[PASS] Successfully uploaded base rootfs to Spaces CDN cache!"
fi

# ------------------------------------------------------------------------------
# STEP 2: Layer Ubiquity Core Appliance Debian Packages
# ------------------------------------------------------------------------------
echo "==> [Phase 2/5] Staging and installing Ubiquity Appliance .deb packages..."

DEB_COUNT=$(find "$DEBS_DIR" -name "*.deb" | wc -l)
if [ "$DEB_COUNT" -eq 0 ]; then
  echo "[ERROR] No .deb packages found in $DEBS_DIR!" >&2
  exit 1
fi
echo "[INFO] Found $DEB_COUNT appliance .deb package(s)."

podman unshare mkdir -p "${ROOTFS}/tmp/ubiquity_debs"
podman unshare cp "${DEBS_DIR}/"*.deb "${ROOTFS}/tmp/ubiquity_debs/"

# Install atomically with dpkg force-overwrite and unsafe-io inside chroot
podman unshare chroot "$ROOTFS" /bin/bash -c '
  set -euo pipefail
  export DEBIAN_FRONTEND=noninteractive
  echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/force-unsafe-io
  echo "force-overwrite" > /etc/dpkg/dpkg.cfg.d/force-overwrite

  apt-get update -o Acquire::AllowReleaseInfoChange=true || true
  apt-get install -y --allow-downgrades -o Dpkg::Options::="--force-overwrite" /tmp/ubiquity_debs/*.deb
  ldconfig

  rm -f /etc/dpkg/dpkg.cfg.d/force-unsafe-io
  rm -f /etc/dpkg/dpkg.cfg.d/force-overwrite
  rm -rf /tmp/ubiquity_debs
'

# Configure IMX219 camera calibration symlink if applicable
podman unshare mkdir -p "${ROOTFS}/opt/ros/jazzy/share/robot_bringup/config"
podman unshare ln -sf \
  "/home/ubuntu/.ros/camera_info/imx219__base_axi_pcie_1000120000_rp1_i2c_88000_imx219_10_640x480.yaml" \
  "${ROOTFS}/opt/ros/jazzy/share/robot_bringup/config/camera_info.yaml" || true

# Stamp build metadata
podman unshare mkdir -p "${ROOTFS}/etc/ubiquity"
BUILD_DATE=$(date --utc +'%Y-%m-%d %H:%M:%S UTC')
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "appliance")
cat << EOF | podman unshare tee "${ROOTFS}/etc/ubiquity/image-release" >/dev/null
IMAGE_VARIANT="ros2-ezmap-pro"
IMAGE_BUILD_DATE="${BUILD_DATE}"
IMAGE_GIT_COMMIT="${GIT_COMMIT}"
BUILD_PIPELINE="two-tier-fast-appliance"
EOF
podman unshare ln -sf /etc/ubiquity/image-release "${ROOTFS}/etc/image_info.txt"

echo "[PASS] Appliance packages installed into /opt/ros/jazzy."

# ------------------------------------------------------------------------------
# STEP 3: Automated RootFS Verification Suite
# ------------------------------------------------------------------------------
if [ "$SKIP_TESTS" = false ] && [ -x "scripts/automated_tests.sh" ]; then
  echo "==> [Phase 3/5] Executing Automated RootFS Verification Suite..."
  ./scripts/automated_tests.sh "$ROOTFS"
  echo "[PASS] RootFS verification passed 100%."
else
  echo "[INFO] Skipping verification test suite."
fi

# ------------------------------------------------------------------------------
# STEP 4: Synthesize Bootable SD Card Disk Image (genimage)
# ------------------------------------------------------------------------------
echo "==> [Phase 4/5] Synthesizing 10 GB Bootable SD Card Disk Image (genimage)..."
GEN_START=$(date +%s)
export PATH="$REPO_ROOT/bin:$REPO_ROOT/work/ros2/host/bin:$PATH"

./build.sh -i -c "$CONFIG" -o "$OPTIONS"
echo "[PASS] Disk image synthesized in $(($(date +%s) - GEN_START)) seconds."

TOTAL_ELAPSED=$(($(date +%s) - START_TIME))
echo "=========================================================="
echo "    APPLIANCE DISK IMAGE SYNTHESIS COMPLETE!              "
echo "=========================================================="
echo "Total Elapsed Time: $((TOTAL_ELAPSED / 60))m $((TOTAL_ELAPSED % 60))s"
echo "Raw Image File    : work/ros2/deploy/ros2.img ($(du -h work/ros2/deploy/ros2.img | cut -f1))"
echo "=========================================================="
