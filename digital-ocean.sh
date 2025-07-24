#!/bin/bash
set -e

# Fixed paths and names
IMG_DIR="work/ros2/deploy"
ORIG_IMAGE="${IMG_DIR}/ros2.img"
BASE_NAME="ros2"

# Generate date and random number
CURRENT_DATE=$(date +%Y%m%d)
RANDOM_NUMBER=$(shuf -i 1000-9999 -n 1)
IMAGE_NAME="${BASE_NAME}_${CURRENT_DATE}_${RANDOM_NUMBER}.img"
COMPRESSED_IMAGE_NAME="${IMAGE_NAME}.xz"
COMPRESSED_IMAGE_FILE="${IMG_DIR}/${COMPRESSED_IMAGE_NAME}"
MASTER_DEST="/buildwork/${COMPRESSED_IMAGE_NAME}"

# 1. Compress the image using xz with all threads and force overwrite
xz -T0 -z -f "${ORIG_IMAGE}"

# 2. Rename the compressed .img.xz to have timestamp and random number
mv "${ORIG_IMAGE}.xz" "${COMPRESSED_IMAGE_FILE}"

UPLOAD_URL=$(python3 generate-presign-key.py "${COMPRESSED_IMAGE_NAME}")
curl --fail -H "x-amz-acl: public-read" --upload-file "${COMPRESSED_IMAGE_FILE}" "${UPLOAD_URL}"

echo "Done."

