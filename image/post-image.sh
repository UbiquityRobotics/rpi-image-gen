#!/bin/bash

set -eu


deploydir=$1

case ${IGconf_image_compression} in
   zstd|none)
      ;;
   *)
      die "Deploy error. Unsupported compression."
      ;;
esac


if [ -f ${IGconf_sys_outputdir}/genimage.cfg ] ; then
   fstabs=()
   opts=()
   fstabs+=("${IGconf_sys_outputdir}"/fstab*)
   for f in "${fstabs[@]}" ; do
      if [ -f "$f" ] ; then
         opts+=('-f' $f)
      fi
   done

   if [ -f ${IGconf_sys_outputdir}/provisionmap.json ] ; then
      opts+=('-m' ${IGconf_sys_outputdir}/provisionmap.json)
   fi
   image2json -g ${IGconf_sys_outputdir}/genimage.cfg "${opts[@]}" > ${IGconf_sys_outputdir}/image.json
fi

msg "Deploying image and SBOM to ${deploydir}"

# Define the known source and desired destination file paths
SRC_IMG="${IGconf_sys_outputdir}/ros2.img"
SRC_SBOM="${IGconf_sys_outputdir}/${IGconf_image_name}.sbom"

DEST_IMG="${deploydir}/${IGconf_image_name}.${IGconf_image_suffix}"
DEST_SBOM="${deploydir}/${IGconf_image_name}.sbom"

# --- Deploy the image file ---
# Check if the source image file actually exists
if [ -f "${SRC_IMG}" ]; then
    # Copy the source file to the destination, renaming it in the process
    msg "Copying ${SRC_IMG} to ${DEST_IMG}"
    cp -v "${SRC_IMG}" "${DEST_IMG}"
else
    # If the source image isn't found, print a clear error and exit
    die "FATAL: Source image ${SRC_IMG} not found!"
fi

# --- Deploy the SBOM file ---
# Check if the source SBOM file exists
if [ -f "${SRC_SBOM}" ]; then
    # Copy the source file to the destination
    msg "Copying ${SRC_SBOM} to ${DEST_SBOM}"
    cp -v "${SRC_SBOM}" "${DEST_SBOM}"
else
    # This is not fatal, so just print a warning
    msg "Warning: SBOM file ${SRC_SBOM} not found."
fi