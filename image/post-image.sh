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


files=()

for f in "${IGconf_sys_outputdir}/${IGconf_image_name}"*.${IGconf_image_suffix} ; do
   files+=($f)
   [[ -f "$f" ]] || continue
   
   # Ensure that the output image is a multiple of the selected sector size
   truncate -s %${IGconf_device_sector_size} $f
done

files+=("${IGconf_sys_outputdir}/${IGconf_image_name}"*.${IGconf_image_suffix}.sparse)
files+=("${IGconf_sys_outputdir}/${IGconf_image_name}"*.sbom)

# --- BEGIN DEBUGGING ---
msg "--- DEBUGGING: Checking for files ---"
msg "Output directory is: ${IGconf_sys_outputdir}"
msg "Looking for image with pattern: ${IGconf_sys_outputdir}/${IGconf_image_name}*.${IGconf_image_suffix}"
msg "Listing all files in output directory:"
ls -l "${IGconf_sys_outputdir}"
msg "List of files found to deploy:"
printf '%s\n' "${files[@]}"
msg "--- END DEBUGGING ---"

msg "Deploying image and SBOM"

for f in "${files[@]}" ; do
   [[ -f "$f" ]] || continue
   case ${IGconf_image_compression} in
      zstd)
         zstd -v -f $f --sparse --output-dir-flat $deploydir
         ;;
      none)
         install -v -D -m 644 $f $deploydir
         ;;
      *)
         ;;
   esac
done
