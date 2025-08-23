#!/bin/bash
set -euo pipefail

# --- Configuration ---

# These variables should be exported by the main build.sh script.
# This allows this deployment script to use the same configuration as the build.
IMG_DIR="${IGconf_sys_deploydir:-deploy}"
BASE_NAME="${IGconf_image_name:-ros2}"
IMAGE_SUFFIX="${IGconf_image_suffix:-img}"
ORIG_IMAGE="${IMG_DIR}/${BASE_NAME}.${IMAGE_SUFFIX}"

# Check if the original image file actually exists before proceeding.
if [ ! -f "${ORIG_IMAGE}" ]; then
    echo "[ERROR] Image file not found: ${ORIG_IMAGE}"
    echo "[ERROR] Make sure the build completed and IGconf_ variables are exported."
    exit 1
fi

# Create a unique name for the compressed image to be uploaded.
CURRENT_DATE=$(date +%Y%m%d)
RANDOM_NUMBER=$(shuf -i 1000-9999 -n 1)
UPLOAD_IMAGE_NAME="${BASE_NAME}_${CURRENT_DATE}_${RANDOM_NUMBER}.${IMAGE_SUFFIX}"
COMPRESSED_IMAGE_NAME="${UPLOAD_IMAGE_NAME}.xz"
COMPRESSED_IMAGE_FILE="${IMG_DIR}/${COMPRESSED_IMAGE_NAME}"
MASTER_DEST="/buildwork/${COMPRESSED_IMAGE_NAME}"

# DigitalOcean Spaces config (passed as env vars)
: "${SPACES_REGION:=sfo2}"                        
: "${SPACES_ENDPOINT:=${SPACES_REGION}.digitaloceanspaces.com}"
: "${SPACES_BUCKET:=ubiquity-pi-image}"            

# Temporary config file for s3cmd
S3CMD_CONFIG_FILE="$(mktemp)"

# Create the s3cmd config file dynamically
#cat > "$S3CMD_CONFIG_FILE" <<EOF
#[default]
#access_key = ${S3_ACCESS_KEY}
#secret_key = ${S3_SECRET_KEY}
#bucket_location = US
#host_base = ${SPACES_ENDPOINT}
#host_bucket = %(bucket)s.${SPACES_ENDPOINT}
#use_https = True
#signature_v2 = False
#EOF

echo "[INFO] Compressing image..."
xz -T0 -z -f "${ORIG_IMAGE}"

echo "[INFO] Renaming compressed image to: ${COMPRESSED_IMAGE_FILE}"
mv "${ORIG_IMAGE}.xz" "${COMPRESSED_IMAGE_FILE}"

echo "[INFO] Uploading to DigitalOcean Spaces bucket: ${SPACES_BUCKET}"

# Upload using s3cmd with the temporary config file
#s3cmd -c "$S3CMD_CONFIG_FILE" put "${COMPRESSED_IMAGE_FILE}" "s3://${SPACES_BUCKET}/${COMPRESSED_IMAGE_NAME}"

echo "[SUCCESS] Upload and processing complete."

