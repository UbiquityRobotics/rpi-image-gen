#!/bin/bash
set -euo pipefail

# --- Configuration ---

IMG_DIR="work/ros2/deploy"
ORIG_IMAGE="${IMG_DIR}/ros2.img"
BASE_NAME="ros2-ezmap-pro"
CURRENT_DATE=$(date +%Y%m%d)
RANDOM_NUMBER=$(shuf -i 1000-9999 -n 1)
IMAGE_NAME="${BASE_NAME}_${CURRENT_DATE}_${RANDOM_NUMBER}.img"
COMPRESSED_IMAGE_NAME="${IMAGE_NAME}.xz"
COMPRESSED_IMAGE_FILE="${IMG_DIR}/${COMPRESSED_IMAGE_NAME}"

# DigitalOcean Spaces config (passed as env vars)
: "${SPACES_REGION:=sfo2}"
: "${SPACES_ENDPOINT:=${SPACES_REGION}.digitaloceanspaces.com}"
: "${SPACES_BUCKET:=ubiquity-pi-image}"

# Determine target file to upload
UPLOAD_FILE=""
if [ $# -ge 1 ] && [ -f "$1" ]; then
    UPLOAD_FILE="$1"
else
    # Check if an already compressed image exists in deploy directory
    UPLOAD_FILE=$(find "$IMG_DIR" -maxdepth 1 \( -name "*.img.xz" -o -name "*.img.zst" \) 2>/dev/null | head -n 1 || true)
fi

# If no compressed image found, but raw image exists, compress it now
if [ -z "$UPLOAD_FILE" ] || [ ! -f "$UPLOAD_FILE" ]; then
    if [ -f "$ORIG_IMAGE" ]; then
        echo "[INFO] Compressing raw image ${ORIG_IMAGE} with multithreaded xz..."
        xz -T0 -z -f "${ORIG_IMAGE}"
        mv "${ORIG_IMAGE}.xz" "${COMPRESSED_IMAGE_FILE}"
        UPLOAD_FILE="${COMPRESSED_IMAGE_FILE}"
    else
        echo "[ERROR] No valid image file found to upload in ${IMG_DIR}!"
        exit 1
    fi
fi

TARGET_KEY=$(basename "$UPLOAD_FILE")
echo "[INFO] Selected image for upload: ${UPLOAD_FILE} -> s3://${SPACES_BUCKET}/${TARGET_KEY}"

# Upload with high-speed parallel boto3 if available, falling back to s3cmd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARALLEL_UPLOADER="${SCRIPT_DIR}/scripts/s3_parallel_upload.py"
UPLOAD_SUCCESS=0

if command -v python3 >/dev/null 2>&1 && python3 -c "import boto3" 2>/dev/null; then
    echo "[INFO] Initiating high-speed parallel multipart upload via boto3 (16 threads)..."
    if python3 "$PARALLEL_UPLOADER" "$UPLOAD_FILE" "$TARGET_KEY"; then
        UPLOAD_SUCCESS=1
    else
        echo "[WARN] boto3 parallel upload failed. Falling back to legacy s3cmd..."
    fi
fi

if [ "$UPLOAD_SUCCESS" -ne 1 ]; then
    echo "[INFO] Uploading using legacy s3cmd single-thread uploader..."
    S3CMD_CONFIG_FILE="$(mktemp)"
    trap 'rm -f "$S3CMD_CONFIG_FILE"' EXIT
    cat > "$S3CMD_CONFIG_FILE" <<EOF
[default]
access_key = ${S3_ACCESS_KEY}
secret_key = ${S3_SECRET_KEY}
bucket_location = US
host_base = ${SPACES_ENDPOINT}
host_bucket = %(bucket)s.${SPACES_ENDPOINT}
use_https = True
signature_v2 = False
EOF
    s3cmd -c "$S3CMD_CONFIG_FILE" put --acl-public "${UPLOAD_FILE}" "s3://${SPACES_BUCKET}/${TARGET_KEY}"
fi

echo "[SUCCESS] Upload and processing complete."
echo "[INFO] Public URL: https://${SPACES_BUCKET}.${SPACES_ENDPOINT}/${TARGET_KEY}"
