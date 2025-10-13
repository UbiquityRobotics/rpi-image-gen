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
MASTER_DEST="/buildwork/${COMPRESSED_IMAGE_NAME}"

# DigitalOcean Spaces config (passed as env vars)
: "${SPACES_REGION:=sfo2}"                        
: "${SPACES_ENDPOINT:=${SPACES_REGION}.digitaloceanspaces.com}"
: "${SPACES_BUCKET:=ubiquity-pi-image}"            

# Temporary config file for s3cmd
S3CMD_CONFIG_FILE="$(mktemp)"

# Create the s3cmd config file dynamically
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

echo "[INFO] Compressing image..."
xz -T0 -z -f "${ORIG_IMAGE}"

echo "[INFO] Renaming compressed image to: ${COMPRESSED_IMAGE_FILE}"
mv "${ORIG_IMAGE}.xz" "${COMPRESSED_IMAGE_FILE}"

echo "[INFO] Uploading to DigitalOcean Spaces bucket: ${SPACES_BUCKET}"

# Upload using s3cmd with the temporary config file
s3cmd -c "$S3CMD_CONFIG_FILE" put --acl-public "${COMPRESSED_IMAGE_FILE}" "s3://${SPACES_BUCKET}/${COMPRESSED_IMAGE_NAME}"

echo "[SUCCESS] Upload and processing complete."

