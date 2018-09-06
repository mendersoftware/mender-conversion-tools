#!/bin/bash

sdimg_primary_dir=$1
embedded_rootfs_dir=$2

[ ! -d "${sdimg_primary_dir}" ] &&  \
    { echo "Error: rootfs location not mounted."; exit 1; }
[ ! -d "${embedded_rootfs_dir}" ] && \
    { echo "Error: embedded content not mounted."; exit 1; }

# Copy rootfs partition.
sudo cp -ar ${embedded_rootfs_dir}/* ${sdimg_primary_dir}

# Add mountpoints.
sudo install -d -m 755 ${sdimg_primary_dir}/boot/efi
sudo install -d -m 755 ${sdimg_primary_dir}/data

echo -e "\nStage done."

exit 0
